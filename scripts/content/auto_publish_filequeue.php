<?php
/**
 * Dependency-free article scheduler for xyptdq.
 *
 * It scans versioned JSON articles in content/scheduled and stores runtime state
 * outside Git. No SQLite extension is required.
 *
 * Safety model:
 * - dry-run is the default;
 * - --commit requires a verified capability manifest and a separate CMS adapter;
 * - the adapter must provide durable idempotency because a process can crash
 *   after the CMS transaction commits but before local state is flushed.
 *
 * Usage:
 *   php scripts/content/auto_publish_filequeue.php
 *   php scripts/content/auto_publish_filequeue.php --commit --limit=2
 */

declare(strict_types=1);

$options = getopt('', [
    'source::',
    'state::',
    'lock::',
    'limit::',
    'commit',
    'capabilities::',
    'adapter::',
]);

$repoRoot = dirname(__DIR__, 2);
$source = $options['source'] ?? ($repoRoot . '/content/scheduled');
$statePath = $options['state'] ?? (getenv('XYPTDQ_PUBLISH_STATE') ?: '/var/lib/xyptdq-publisher/state.json');
$lockPath = $options['lock'] ?? (getenv('XYPTDQ_PUBLISH_LOCK') ?: '/var/lib/xyptdq-publisher/publisher.lock');
$limit = max(1, min(20, (int) ($options['limit'] ?? 2)));
$commit = array_key_exists('commit', $options);
$capabilitiesPath = $options['capabilities'] ?? ($repoRoot . '/config/publisher_capabilities.json');
$adapterPath = $options['adapter'] ?? ($repoRoot . '/scripts/content/cms_publish_adapter.php');

function publisherFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[filequeue] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function atomicJsonWrite(string $path, array $data): void
{
    $dir = dirname($path);
    if (!is_dir($dir) && !mkdir($dir, 0750, true) && !is_dir($dir)) {
        throw new RuntimeException('cannot create state directory: ' . $dir);
    }
    $json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode runtime state');
    }
    $tmp = $path . '.tmp.' . getmypid();
    if (file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary state: ' . $tmp);
    }
    @chmod($tmp, 0640);
    if (!rename($tmp, $path)) {
        @unlink($tmp);
        throw new RuntimeException('cannot atomically replace state file');
    }
}

function loadState(string $path): array
{
    if (!is_file($path)) {
        return [
            'version' => 1,
            'updated_at' => gmdate('c'),
            'articles' => [],
        ];
    }
    $raw = file_get_contents($path);
    $state = $raw === false ? null : json_decode($raw, true);
    if (!is_array($state) || !isset($state['articles']) || !is_array($state['articles'])) {
        throw new RuntimeException('invalid state file: ' . $path);
    }
    return $state;
}

function canonicalArticleHash(array $article): string
{
    $canonical = json_encode($article, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($canonical === false) {
        throw new RuntimeException('cannot encode article for hashing');
    }
    return hash('sha256', $canonical);
}

function validateArticle(array $article, string $file): array
{
    foreach (['schema_version', 'article_key', 'title', 'content', 'catid', 'publish_at'] as $field) {
        if (!array_key_exists($field, $article) || $article[$field] === '') {
            throw new RuntimeException($file . ': required field missing: ' . $field);
        }
    }
    if ((int) $article['schema_version'] !== 1) {
        throw new RuntimeException($file . ': unsupported schema_version');
    }
    $key = (string) $article['article_key'];
    if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', $key)) {
        throw new RuntimeException($file . ': invalid article_key');
    }
    if (mb_strlen(trim((string) $article['title']), 'UTF-8') < 8) {
        throw new RuntimeException($file . ': title is too short');
    }
    if (mb_strlen(strip_tags((string) $article['content']), 'UTF-8') < 180) {
        throw new RuntimeException($file . ': content is too thin');
    }
    if ((int) $article['catid'] <= 0) {
        throw new RuntimeException($file . ': invalid catid');
    }
    try {
        $publishAt = new DateTimeImmutable((string) $article['publish_at']);
    } catch (Throwable $e) {
        throw new RuntimeException($file . ': invalid publish_at');
    }

    $article['_source_file'] = basename($file);
    $article['_publish_at_iso'] = $publishAt->format(DateTimeInterface::ATOM);
    $article['_publish_at_ts'] = $publishAt->getTimestamp();
    $article['_content_hash'] = canonicalArticleHash(array_diff_key($article, array_flip([
        '_source_file', '_publish_at_iso', '_publish_at_ts', '_content_hash'
    ])));
    return $article;
}

function loadArticles(string $source): array
{
    if (!is_dir($source)) {
        throw new RuntimeException('source directory not found: ' . $source);
    }
    $files = glob(rtrim($source, '/') . '/*.json') ?: [];
    sort($files, SORT_STRING);
    $articles = [];
    foreach ($files as $file) {
        $raw = file_get_contents($file);
        $data = $raw === false ? null : json_decode($raw, true);
        if (!is_array($data) || json_last_error() !== JSON_ERROR_NONE) {
            throw new RuntimeException(basename($file) . ': invalid JSON: ' . json_last_error_msg());
        }
        $article = validateArticle($data, basename($file));
        $key = (string) $article['article_key'];
        if (isset($articles[$key])) {
            throw new RuntimeException('duplicate article_key across scheduled files: ' . $key);
        }
        $articles[$key] = $article;
    }
    return $articles;
}

$lockDir = dirname($lockPath);
if (!is_dir($lockDir) && !mkdir($lockDir, 0750, true) && !is_dir($lockDir)) {
    publisherFail('cannot create lock directory: ' . $lockDir);
}
$lockHandle = fopen($lockPath, 'c+');
if ($lockHandle === false || !flock($lockHandle, LOCK_EX | LOCK_NB)) {
    publisherFail('another publisher process is already running', 10);
}
@chmod($lockPath, 0640);

try {
    $state = loadState($statePath);
    $articles = loadArticles($source);
    $now = time();
    $due = [];

    foreach ($articles as $key => $article) {
        $entry = $state['articles'][$key] ?? [
            'status' => 'scheduled',
            'content_hash' => $article['_content_hash'],
            'cms_id' => null,
            'published_at' => null,
            'retry_count' => 0,
            'last_error' => null,
        ];

        if (($entry['status'] ?? '') === 'published') {
            if (($entry['content_hash'] ?? '') !== $article['_content_hash']) {
                fwrite(STDERR, '[filequeue] WARN: published article changed in Git; no republish: ' . $key . PHP_EOL);
            }
            $state['articles'][$key] = $entry;
            continue;
        }

        if (($entry['status'] ?? '') === 'publishing') {
            $started = strtotime((string) ($entry['publishing_since'] ?? '')) ?: 0;
            if ($started > 0 && ($now - $started) > 1800) {
                $entry['status'] = 'scheduled';
                $entry['last_error'] = 'recovered stale publishing state; durable CMS idempotency must decide whether publish already committed';
            }
        }

        if (($entry['status'] ?? '') === 'failed' && (int) ($entry['retry_count'] ?? 0) >= 3) {
            $state['articles'][$key] = $entry;
            continue;
        }

        $entry['content_hash'] = $article['_content_hash'];
        $state['articles'][$key] = $entry;

        if ($article['_publish_at_ts'] <= $now && in_array($entry['status'], ['scheduled', 'failed'], true)) {
            $due[] = $article;
        }
    }

    usort($due, static function (array $a, array $b): int {
        $cmp = $a['_publish_at_ts'] <=> $b['_publish_at_ts'];
        return $cmp !== 0 ? $cmp : strcmp((string) $a['article_key'], (string) $b['article_key']);
    });
    $due = array_slice($due, 0, $limit);

    fwrite(STDOUT, sprintf('[filequeue] source=%d due=%d limit=%d mode=%s%s', count($articles), count($due), $limit, $commit ? 'COMMIT' : 'DRY-RUN', PHP_EOL));
    foreach ($due as $article) {
        fwrite(STDOUT, sprintf('  %s | %s | publish_at=%s%s', $article['article_key'], $article['title'], $article['_publish_at_iso'], PHP_EOL));
    }

    if (!$commit) {
        exit(0);
    }

    if (!is_file($capabilitiesPath)) {
        throw new RuntimeException('capability manifest missing: ' . $capabilitiesPath);
    }
    $capabilities = json_decode((string) file_get_contents($capabilitiesPath), true);
    if (!is_array($capabilities) || ($capabilities['verified'] ?? false) !== true) {
        throw new RuntimeException('CMS write path remains locked: capability manifest is not verified');
    }
    if (($capabilities['durable_idempotency_verified'] ?? false) !== true) {
        throw new RuntimeException('CMS write path remains locked: durable idempotency is not verified');
    }
    if (!is_file($adapterPath)) {
        throw new RuntimeException('CMS adapter missing: ' . $adapterPath);
    }
    require_once $adapterPath;
    if (!function_exists('xyptdq_publish_article')) {
        throw new RuntimeException('CMS adapter must define xyptdq_publish_article(array $article): array');
    }

    foreach ($due as $article) {
        $key = (string) $article['article_key'];
        $entry = $state['articles'][$key];
        $entry['status'] = 'publishing';
        $entry['publishing_since'] = gmdate('c');
        $entry['last_error'] = null;
        $state['articles'][$key] = $entry;
        $state['updated_at'] = gmdate('c');
        atomicJsonWrite($statePath, $state);

        try {
            $result = xyptdq_publish_article($article);
            $cmsId = (int) ($result['cms_id'] ?? 0);
            if ($cmsId <= 0) {
                throw new RuntimeException('adapter returned invalid cms_id');
            }
            $entry['status'] = 'published';
            $entry['cms_id'] = $cmsId;
            $entry['published_at'] = gmdate('c');
            $entry['publishing_since'] = null;
            $entry['last_error'] = null;
            $state['articles'][$key] = $entry;
            $state['updated_at'] = gmdate('c');
            atomicJsonWrite($statePath, $state);
            fwrite(STDOUT, sprintf('[filequeue] PUBLISHED key=%s cms_id=%d%s', $key, $cmsId, PHP_EOL));
        } catch (Throwable $e) {
            $entry['status'] = 'failed';
            $entry['retry_count'] = (int) ($entry['retry_count'] ?? 0) + 1;
            $entry['publishing_since'] = null;
            $entry['last_error'] = mb_substr($e->getMessage(), 0, 1000, 'UTF-8');
            $state['articles'][$key] = $entry;
            $state['updated_at'] = gmdate('c');
            atomicJsonWrite($statePath, $state);
            fwrite(STDERR, sprintf('[filequeue] FAILED key=%s retry=%d error=%s%s', $key, $entry['retry_count'], $entry['last_error'], PHP_EOL));
        }
    }
} catch (Throwable $e) {
    publisherFail($e->getMessage());
} finally {
    if (is_resource($lockHandle)) {
        flock($lockHandle, LOCK_UN);
        fclose($lockHandle);
    }
}

<?php
/**
 * Explicit one-article production smoke test for the Xunrui adapter.
 *
 * Dry run:
 *   php scripts/content/publisher_smoke.php --article=content/smoke/ffc-betting-basics-risk-v1.json
 *
 * Commit (must be deliberate):
 *   php scripts/content/publisher_smoke.php --article=content/smoke/ffc-betting-basics-risk-v1.json --commit
 *
 * Dry-run is read-only but now validates the target category against the live
 * CMS database, so a category-model mismatch cannot hide until commit mode.
 *
 * In commit mode the same article is submitted twice. The second call MUST
 * return the same cms_id with idempotent=true, proving durable duplicate
 * protection in the production database.
 */

declare(strict_types=1);

$options = getopt('', ['article:', 'commit']);
$articlePath = $options['article'] ?? '';
$commit = array_key_exists('commit', $options);

function smokeFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[publisher-smoke] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

if ($articlePath === '' || !is_file($articlePath)) {
    smokeFail('--article must point to an existing JSON article');
}
$raw = file_get_contents($articlePath);
$article = $raw === false ? null : json_decode($raw, true);
if (!is_array($article) || json_last_error() !== JSON_ERROR_NONE) {
    smokeFail('invalid article JSON');
}
foreach (['schema_version', 'article_key', 'title', 'content', 'catid', 'publish_at'] as $required) {
    if (!array_key_exists($required, $article) || $article[$required] === '') {
        smokeFail('missing required field: ' . $required);
    }
}
if ((int) $article['schema_version'] !== 1) {
    smokeFail('unsupported schema_version');
}
if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', (string) $article['article_key'])) {
    smokeFail('invalid article_key');
}
if (mb_strlen(strip_tags((string) $article['content']), 'UTF-8') < 180) {
    smokeFail('content too thin');
}

$article['_source_file'] = basename($articlePath);
$copy = $article;
unset($copy['_source_file']);
$encoded = json_encode($copy, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($encoded === false) {
    smokeFail('cannot calculate content hash');
}
$article['_content_hash'] = hash('sha256', $encoded);

fwrite(STDOUT, sprintf(
    "[publisher-smoke] key=%s catid=%d title=%s mode=%s\n",
    (string) $article['article_key'],
    (int) $article['catid'],
    (string) $article['title'],
    $commit ? 'COMMIT' : 'DRY-RUN'
));

$adapter = __DIR__ . '/cms_publish_adapter.php';
if (!is_file($adapter)) {
    smokeFail('adapter missing');
}
require_once $adapter;
if (!function_exists('xyptdq_publish_article') || !function_exists('xyptdq_resolve_category')) {
    smokeFail('adapter function missing');
}

// Read-only live target preflight. This deliberately performs no DDL or DML.
try {
    $config = xyptdq_load_db_config();
    $database = xyptdq_identifier((string) $config['database'], 'database');
    $prefix = (string) ($config['DBPrefix'] ?? 'dr_');
    if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix)) {
        smokeFail('unsafe database table prefix');
    }
    $module = xyptdq_identifier(getenv('XYPTDQ_CMS_MODULE') ?: '1_news', 'module');
    $newsTable = xyptdq_identifier($prefix . $module, 'news table');
    $pdo = xyptdq_open_pdo($config);
    $resolved = xyptdq_resolve_category(
        $pdo,
        $database,
        $prefix,
        $module,
        $newsTable,
        (int) $article['catid']
    );
    $categorySource = (string) ($resolved['source'] ?? '');
    if ($categorySource === '') {
        smokeFail('category preflight returned no source');
    }
    fwrite(STDOUT, '[publisher-smoke] TARGET_PREFLIGHT PASS category_source=' . $categorySource . PHP_EOL);
} catch (Throwable $e) {
    smokeFail('target preflight failed: ' . $e->getMessage());
}

if (!$commit) {
    fwrite(STDOUT, "[publisher-smoke] DRY-RUN ONLY; no database write attempted.\n");
    exit(0);
}

try {
    $first = xyptdq_publish_article($article);
    $second = xyptdq_publish_article($article);
} catch (Throwable $e) {
    smokeFail($e->getMessage());
}

$firstId = (int) ($first['cms_id'] ?? 0);
$secondId = (int) ($second['cms_id'] ?? 0);
if ($firstId <= 0 || $firstId !== $secondId) {
    smokeFail('idempotency invariant failed: cms_id mismatch');
}
if (($second['idempotent'] ?? false) !== true) {
    smokeFail('second publish did not report durable idempotency');
}

fwrite(STDOUT, sprintf(
    "[publisher-smoke] PASS cms_id=%d first_idempotent=%s second_idempotent=true url=%s\n",
    $firstId,
    (($first['idempotent'] ?? false) ? 'true' : 'false'),
    (string) ($second['url'] ?? '')
));

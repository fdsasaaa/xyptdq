<?php
/**
 * Import versioned article JSON files into a local SQLite queue.
 * This script does NOT publish anything to the CMS.
 *
 * Usage:
 *   php scripts/content/import_articles.php \
 *     --source=/root/xyptdq/content/scheduled \
 *     --queue=/var/lib/xyptdq/article_queue.sqlite
 */

declare(strict_types=1);

$options = getopt('', ['source::', 'queue::']);
$source = $options['source'] ?? (__DIR__ . '/../../content/scheduled');
$queuePath = $options['queue'] ?? (getenv('XYPTDQ_QUEUE') ?: '/var/lib/xyptdq/article_queue.sqlite');

function stop(string $message, int $code = 1): void
{
    fwrite(STDERR, '[import] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function normalizeKeywords(array $article): string
{
    $keywords = [];
    $primary = trim((string) ($article['primary_keyword'] ?? ''));
    if ($primary !== '') {
        $keywords[] = $primary;
    }
    foreach (($article['secondary_keywords'] ?? []) as $keyword) {
        $keyword = trim((string) $keyword);
        if ($keyword !== '' && !in_array($keyword, $keywords, true)) {
            $keywords[] = $keyword;
        }
    }
    return implode(',', array_slice($keywords, 0, 12));
}

function validateArticle(array $article, string $file): void
{
    foreach (['schema_version', 'article_key', 'title', 'content', 'catid', 'publish_at'] as $field) {
        if (!array_key_exists($field, $article) || $article[$field] === '') {
            stop($file . ': required field missing: ' . $field);
        }
    }
    if ((int) $article['schema_version'] !== 1) {
        stop($file . ': unsupported schema_version');
    }
    if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', (string) $article['article_key'])) {
        stop($file . ': invalid article_key');
    }
    if (mb_strlen((string) $article['title'], 'UTF-8') < 8) {
        stop($file . ': title is too short');
    }
    if (mb_strlen(strip_tags((string) $article['content']), 'UTF-8') < 180) {
        stop($file . ': content is too thin; refusing to enqueue');
    }
    if ((int) $article['catid'] <= 0) {
        stop($file . ': invalid catid');
    }
    if (strtotime((string) $article['publish_at']) === false) {
        stop($file . ': invalid publish_at');
    }
}

if (!extension_loaded('pdo_sqlite')) {
    stop('pdo_sqlite extension is not installed.');
}
if (!is_dir($source)) {
    stop('source directory not found: ' . $source);
}

$queueDir = dirname($queuePath);
if (!is_dir($queueDir) && !mkdir($queueDir, 0750, true) && !is_dir($queueDir)) {
    stop('cannot create queue directory: ' . $queueDir);
}

$pdo = new PDO('sqlite:' . $queuePath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$pdo->exec('PRAGMA journal_mode=WAL');
$pdo->exec('PRAGMA foreign_keys=ON');
$pdo->exec(
    "CREATE TABLE IF NOT EXISTS article_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        article_key TEXT NOT NULL UNIQUE,
        source_file TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        title TEXT NOT NULL,
        slug TEXT,
        content TEXT NOT NULL,
        excerpt TEXT,
        seo_title TEXT,
        meta_description TEXT,
        keywords TEXT,
        catid INTEGER NOT NULL,
        thumbnail TEXT,
        publish_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'scheduled' CHECK(status IN ('draft','scheduled','publishing','published','failed')),
        cms_id INTEGER,
        retry_count INTEGER NOT NULL DEFAULT 0,
        error_log TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        published_at TEXT
    )"
);
$pdo->exec('CREATE INDEX IF NOT EXISTS idx_article_queue_status_publish_at ON article_queue(status, publish_at)');
$pdo->exec('CREATE UNIQUE INDEX IF NOT EXISTS idx_article_queue_slug ON article_queue(slug) WHERE slug IS NOT NULL AND slug <> \'\'');

$files = glob(rtrim($source, '/') . '/*.json') ?: [];
sort($files, SORT_STRING);

$inserted = 0;
$updated = 0;
$unchanged = 0;
$skippedPublished = 0;

$pdo->beginTransaction();
try {
    $select = $pdo->prepare('SELECT id, content_hash, status FROM article_queue WHERE article_key = :article_key');
    $insert = $pdo->prepare(
        "INSERT INTO article_queue
        (article_key, source_file, content_hash, title, slug, content, excerpt, seo_title, meta_description, keywords, catid, thumbnail, publish_at, status)
        VALUES
        (:article_key, :source_file, :content_hash, :title, :slug, :content, :excerpt, :seo_title, :meta_description, :keywords, :catid, :thumbnail, :publish_at, 'scheduled')"
    );
    $update = $pdo->prepare(
        "UPDATE article_queue SET
          source_file=:source_file, content_hash=:content_hash, title=:title, slug=:slug,
          content=:content, excerpt=:excerpt, seo_title=:seo_title,
          meta_description=:meta_description, keywords=:keywords, catid=:catid,
          thumbnail=:thumbnail, publish_at=:publish_at, updated_at=CURRENT_TIMESTAMP
         WHERE article_key=:article_key AND status <> 'published'"
    );

    foreach ($files as $file) {
        $raw = file_get_contents($file);
        if ($raw === false) {
            stop('cannot read: ' . $file);
        }
        $article = json_decode($raw, true);
        if (!is_array($article) || json_last_error() !== JSON_ERROR_NONE) {
            stop($file . ': invalid JSON: ' . json_last_error_msg());
        }
        validateArticle($article, basename($file));

        $canonicalJson = json_encode($article, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $hash = hash('sha256', (string) $canonicalJson);
        $params = [
            ':article_key' => (string) $article['article_key'],
            ':source_file' => basename($file),
            ':content_hash' => $hash,
            ':title' => trim((string) $article['title']),
            ':slug' => isset($article['slug']) && trim((string) $article['slug']) !== '' ? trim((string) $article['slug']) : null,
            ':content' => (string) $article['content'],
            ':excerpt' => trim((string) ($article['excerpt'] ?? '')),
            ':seo_title' => trim((string) ($article['seo_title'] ?? $article['title'])),
            ':meta_description' => trim((string) ($article['meta_description'] ?? $article['excerpt'] ?? '')),
            ':keywords' => normalizeKeywords($article),
            ':catid' => (int) $article['catid'],
            ':thumbnail' => trim((string) ($article['thumbnail'] ?? '')),
            ':publish_at' => (new DateTimeImmutable((string) $article['publish_at']))->format(DateTimeInterface::ATOM),
        ];

        $select->execute([':article_key' => $params[':article_key']]);
        $existing = $select->fetch(PDO::FETCH_ASSOC);
        if (!$existing) {
            $insert->execute($params);
            $inserted++;
            continue;
        }
        if ($existing['content_hash'] === $hash) {
            $unchanged++;
            continue;
        }
        if ($existing['status'] === 'published') {
            fwrite(STDERR, '[import] WARN: published article changed in Git; queue not overwritten: ' . $params[':article_key'] . PHP_EOL);
            $skippedPublished++;
            continue;
        }
        $update->execute($params);
        $updated++;
    }
    $pdo->commit();
} catch (Throwable $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    stop($e->getMessage());
}

@chmod($queuePath, 0640);
fwrite(STDOUT, sprintf(
    "[import] OK files=%d inserted=%d updated=%d unchanged=%d published_skipped=%d queue=%s\n",
    count($files), $inserted, $updated, $unchanged, $skippedPublished, $queuePath
));

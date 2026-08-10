<?php
/**
 * Article queue controller.
 *
 * Current safety state:
 * - --dry-run (default): lists due articles only.
 * - --commit: deliberately refuses to write until config/publisher_capabilities.json
 *   has been verified against a known-good CMS publish probe.
 *
 * This prevents an unverified direct-DB publisher from corrupting Xunrui CMS
 * auxiliary indexes merely because dr_1_news + dr_1_news_data_0 are known.
 */

declare(strict_types=1);

$options = getopt('', ['queue::', 'limit::', 'commit', 'capabilities::']);
$queuePath = $options['queue'] ?? (getenv('XYPTDQ_QUEUE') ?: '/var/lib/xyptdq/article_queue.sqlite');
$limit = max(1, min(20, (int) ($options['limit'] ?? 2)));
$commit = array_key_exists('commit', $options);
$capabilitiesPath = $options['capabilities'] ?? (__DIR__ . '/../../config/publisher_capabilities.json');

function abortPublish(string $message, int $code = 1): void
{
    fwrite(STDERR, '[publisher] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

if (!is_file($queuePath)) {
    abortPublish('queue not found: ' . $queuePath . '; run import_articles.php first');
}
if (!extension_loaded('pdo_sqlite')) {
    abortPublish('pdo_sqlite extension is not installed');
}

$queue = new PDO('sqlite:' . $queuePath, null, null, [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]);
$queue->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

$now = (new DateTimeImmutable('now'))->format(DateTimeInterface::ATOM);
$stmt = $queue->prepare(
    "SELECT id, article_key, title, publish_at, catid, status, retry_count, cms_id
     FROM article_queue
     WHERE status='scheduled' AND publish_at <= :now
     ORDER BY publish_at ASC, id ASC
     LIMIT " . $limit
);
$stmt->execute([':now' => $now]);
$due = $stmt->fetchAll();

if (!$due) {
    fwrite(STDOUT, '[publisher] OK: no due articles' . PHP_EOL);
    exit(0);
}

fwrite(STDOUT, '[publisher] due=' . count($due) . ' now=' . $now . PHP_EOL);
foreach ($due as $article) {
    fwrite(STDOUT, sprintf(
        "  #%d %s | %s | publish_at=%s | catid=%d\n",
        (int) $article['id'],
        (string) $article['article_key'],
        (string) $article['title'],
        (string) $article['publish_at'],
        (int) $article['catid']
    ));
}

if (!$commit) {
    fwrite(STDOUT, '[publisher] DRY-RUN only. No CMS write was attempted.' . PHP_EOL);
    exit(0);
}

if (!is_file($capabilitiesPath)) {
    abortPublish('capability manifest missing: ' . $capabilitiesPath);
}
$capabilities = json_decode((string) file_get_contents($capabilitiesPath), true);
if (!is_array($capabilities)) {
    abortPublish('invalid capability manifest JSON');
}
if (($capabilities['verified'] ?? false) !== true) {
    abortPublish(
        'CMS write path is intentionally locked. Run publisher_probe.php on a known-good manually published article, ' .
        'verify all required auxiliary table writes, then update publisher_capabilities.json and the CMS adapter.'
    );
}

abortPublish(
    'Capability manifest says verified, but the production CMS write adapter has not yet been committed. ' .
    'This is a deliberate fail-closed state.',
    2
);

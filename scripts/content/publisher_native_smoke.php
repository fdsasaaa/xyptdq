<?php
/** Explicit production smoke for the Xunrui-native publisher adapter. */
declare(strict_types=1);

$options = getopt('', ['article:', 'commit', 'offline']);
$articlePath = $options['article'] ?? '';
$commit = array_key_exists('commit', $options);
$offline = array_key_exists('offline', $options);

function nativeSmokeFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[publisher-native-smoke] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

if ($commit && $offline) {
    nativeSmokeFail('--offline cannot be combined with --commit');
}
if ($articlePath === '' || !is_file($articlePath)) {
    nativeSmokeFail('--article must point to an existing JSON article');
}
$data = json_decode((string) file_get_contents($articlePath), true);
if (!is_array($data) || json_last_error() !== JSON_ERROR_NONE) {
    nativeSmokeFail('invalid article JSON');
}
foreach (['schema_version', 'article_key', 'title', 'content', 'catid', 'publish_at'] as $required) {
    if (!array_key_exists($required, $data) || $data[$required] === '') {
        nativeSmokeFail('missing required field: ' . $required);
    }
}
if ((int) $data['schema_version'] !== 1) {
    nativeSmokeFail('unsupported schema_version');
}
if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', (string) $data['article_key'])) {
    nativeSmokeFail('invalid article_key');
}
if (mb_strlen(strip_tags((string) $data['content']), 'UTF-8') < 180) {
    nativeSmokeFail('content too thin');
}
$data['_source_file'] = basename($articlePath);
$copy = $data;
unset($copy['_source_file']);
$encoded = json_encode($copy, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($encoded === false) {
    nativeSmokeFail('cannot calculate content hash');
}
$data['_content_hash'] = hash('sha256', $encoded);

$mode = $commit ? 'COMMIT' : ($offline ? 'OFFLINE' : 'DRY-RUN');
fwrite(STDOUT, sprintf(
    "[publisher-native-smoke] key=%s catid=%d title=%s mode=%s\n",
    (string) $data['article_key'],
    (int) $data['catid'],
    (string) $data['title'],
    $mode
));
if ($offline) {
    fwrite(STDOUT, "[publisher-native-smoke] OFFLINE FIXTURE PASS; no database connection or write attempted.\n");
    exit(0);
}

$adapter = __DIR__ . '/cms_publish_native_adapter.php';
if (!is_file($adapter)) {
    nativeSmokeFail('native adapter missing');
}
require_once $adapter;

try {
    $config = xyptdq_native_load_db_config();
    $database = xyptdq_native_identifier((string) $config['database'], 'database');
    $prefix = (string) ($config['DBPrefix'] ?? 'dr_');
    $layout = xyptdq_native_layout($config);
    $pdo = xyptdq_native_open_pdo($config);
    $resolved = xyptdq_native_resolve_category(
        $pdo,
        $database,
        $prefix,
        $layout['module'],
        $layout['news'],
        (int) $data['catid']
    );
    xyptdq_native_assert_allocator_safe($pdo, $database, $prefix, $layout);
    $source = (string) ($resolved['source'] ?? '');
    if ($source === '') {
        nativeSmokeFail('category preflight returned no source');
    }
    fwrite(STDOUT, '[publisher-native-smoke] TARGET_PREFLIGHT PASS category_source=' . $source . PHP_EOL);
    fwrite(STDOUT, "[publisher-native-smoke] ALLOCATOR_PREFLIGHT PASS\n");
} catch (Throwable $e) {
    nativeSmokeFail('target preflight failed: ' . $e->getMessage());
}

if (!$commit) {
    fwrite(STDOUT, "[publisher-native-smoke] DRY-RUN ONLY; no CMS write attempted.\n");
    exit(0);
}

try {
    $first = xyptdq_publish_article($data);
    $second = xyptdq_publish_article($data);
} catch (Throwable $e) {
    nativeSmokeFail($e->getMessage());
}
$firstId = (int) ($first['cms_id'] ?? 0);
$secondId = (int) ($second['cms_id'] ?? 0);
if ($firstId <= 0 || $firstId !== $secondId) {
    nativeSmokeFail('idempotency invariant failed: cms_id mismatch');
}
if (($second['idempotent'] ?? false) !== true) {
    nativeSmokeFail('second publish did not report durable idempotency');
}
fwrite(STDOUT, sprintf(
    "[publisher-native-smoke] PASS cms_id=%d first_idempotent=%s second_idempotent=true url=%s\n",
    $firstId,
    (($first['idempotent'] ?? false) ? 'true' : 'false'),
    (string) ($second['url'] ?? '')
));

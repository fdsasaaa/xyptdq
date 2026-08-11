#!/usr/bin/env php
<?php
declare(strict_types=1);

$repoRoot = dirname(__DIR__, 2);
$converter = __DIR__ . '/convert_approved_to_draft.php';
$input = $repoRoot . '/content/ingress/smoke-batch2/LCM-IDEA-48eb8743fbbbad11.json';
$committedPath = $repoRoot . '/content/drafts/lcm-idea-48eb8743fbbbad11.json';
$tmpRoot = sys_get_temp_dir() . '/xyptdq-metadata-refresh-' . getmypid();

function refreshFail(string $message): void
{
    fwrite(STDERR, '[metadata-refresh] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function refreshLoad(string $path): array
{
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data)) {
        refreshFail('invalid JSON: ' . $path);
    }
    return $data;
}

function refreshWrite(string $path, array $data): void
{
    $json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($path, $json . PHP_EOL) === false) {
        refreshFail('cannot write temp JSON: ' . $path);
    }
}

function runRefresh(string $converter, string $input, string $output, bool $refresh): array
{
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($input)
        . ' --output=' . escapeshellarg($output)
        . ($refresh ? ' --refresh-metadata' : '');
    $lines = [];
    $code = 0;
    exec($cmd . ' 2>&1', $lines, $code);
    return ['code' => $code, 'output' => implode("\n", $lines)];
}

if (!mkdir($tmpRoot, 0750, true) && !is_dir($tmpRoot)) {
    refreshFail('cannot create temp directory');
}

try {
    $expected = refreshLoad($committedPath);

    // Default behavior remains idempotent/unchanged even when metadata is stale.
    $defaultPath = $tmpRoot . '/default.json';
    $stale = $expected;
    $stale['title'] = '旧标题';
    $stale['seo_title'] = '旧SEO标题';
    $stale['primary_keyword'] = '旧主关键词';
    refreshWrite($defaultPath, $stale);
    $defaultRun = runRefresh($converter, $input, $defaultPath, false);
    if ($defaultRun['code'] !== 0 || strpos($defaultRun['output'], '"status": "unchanged"') === false) {
        refreshFail('default converter behavior changed unexpectedly');
    }
    if ((refreshLoad($defaultPath)['primary_keyword'] ?? '') !== '旧主关键词') {
        refreshFail('default mode unexpectedly rewrote metadata');
    }

    // Explicit refresh may replace metadata only when content identity is exact.
    $refreshPath = $tmpRoot . '/refresh.json';
    refreshWrite($refreshPath, $stale);
    $refreshRun = runRefresh($converter, $input, $refreshPath, true);
    if ($refreshRun['code'] !== 0 || strpos($refreshRun['output'], 'draft_metadata_refreshed') === false) {
        refreshFail('safe metadata refresh was rejected: ' . $refreshRun['output']);
    }
    $actual = refreshLoad($refreshPath);
    unset($actual['converted_at'], $expected['converted_at']);
    if ($actual != $expected) {
        refreshFail('safe metadata refresh did not reproduce committed draft');
    }

    // Same stored hash is not enough: content bytes must also match exactly.
    $contentPath = $tmpRoot . '/tampered-content.json';
    $tampered = $expected;
    $tampered['content'] .= '<p>tampered</p>';
    refreshWrite($contentPath, $tampered);
    $contentRun = runRefresh($converter, $input, $contentPath, true);
    if ($contentRun['code'] === 0 || strpos($contentRun['output'], 'content bytes differ') === false) {
        refreshFail('tampered content was not rejected');
    }

    // Fingerprint is immutable across a metadata-only refresh.
    $fingerprintPath = $tmpRoot . '/bad-fingerprint.json';
    $badFingerprint = $expected;
    $badFingerprint['source_fingerprint'] = str_repeat('0', 64);
    refreshWrite($fingerprintPath, $badFingerprint);
    $fingerprintRun = runRefresh($converter, $input, $fingerprintPath, true);
    if ($fingerprintRun['code'] === 0 || strpos($fingerprintRun['output'], 'source_fingerprint mismatch') === false) {
        refreshFail('fingerprint mismatch was not rejected');
    }

    // Anything already carrying a schedule marker is outside this draft-only path.
    $scheduledPath = $tmpRoot . '/scheduled-marker.json';
    $scheduled = $expected;
    $scheduled['publish_at'] = '2026-08-12T00:00:00+00:00';
    refreshWrite($scheduledPath, $scheduled);
    $scheduledRun = runRefresh($converter, $input, $scheduledPath, true);
    if ($scheduledRun['code'] === 0 || strpos($scheduledRun['output'], 'refuses a draft with publish_at') === false) {
        refreshFail('publish_at draft was not rejected');
    }
} finally {
    foreach (glob($tmpRoot . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmpRoot);
}

fwrite(STDOUT, "[metadata-refresh] PASS safe_metadata_only=1 content_revision=blocked fingerprint_change=blocked publish_at=blocked\n");

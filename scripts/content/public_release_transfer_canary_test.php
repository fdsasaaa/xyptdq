#!/usr/bin/env php
<?php
declare(strict_types=1);

function transferTestFail(string $message): void
{
    fwrite(STDERR, '[public-release-transfer-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

$repoRoot = dirname(__DIR__, 2);
$ingest = __DIR__ . '/ingest_public_release_transfer_canary.php';
$base = $repoRoot . '/content/ingress/public-release/CF50-20260813';
$revision = $base . '/LCM-CREATOR-cf50-20260813-001.public-r1.json';
$evidence = $base . '/LCM-CREATOR-cf50-20260813-001.parent-evidence.json';
$manifest = $base . '/manifest.json';
$map = $repoRoot . '/content/seo_editorial_cluster_map_cf50.json';
$tmp = sys_get_temp_dir() . '/xyptdq-transfer-canary-' . getmypid();
if (!mkdir($tmp, 0750, true) && !is_dir($tmp)) {
    transferTestFail('cannot create temp directory');
}
$draft = $tmp . '/draft.json';
$badEvidence = $tmp . '/bad-evidence.json';
$badDraft = $tmp . '/bad-draft.json';

try {
    foreach ([$revision, $evidence, $manifest, $map, $ingest] as $path) {
        if (!is_file($path)) {
            transferTestFail('required fixture missing: ' . $path);
        }
    }

    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($ingest)
        . ' --revision=' . escapeshellarg($revision)
        . ' --parent-evidence=' . escapeshellarg($evidence)
        . ' --manifest=' . escapeshellarg($manifest)
        . ' --editorial-cluster-map=' . escapeshellarg($map)
        . ' --output=' . escapeshellarg($draft);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code !== 0) {
        transferTestFail('valid transfer canary failed: ' . implode("\n", $out));
    }

    $payload = json_decode((string) file_get_contents($draft), true);
    if (!is_array($payload)) {
        transferTestFail('generated Draft is invalid');
    }
    $expected = [
        'publication_state' => 'draft',
        'source_article_id' => 'LCM-CREATOR-cf50-20260813-001',
        'source_revision_id' => 'LCM-CREATOR-cf50-20260813-001:public-r1',
        'source_batch_id' => 'CF50-20260813',
        'site_category_key' => 'tzjq',
        'primary_seo_cluster_id' => 'ffc_research',
        'source_parent_evidence_kind' => 'immutable_approved_parent_identity',
        'source_parent_evidence_repository' => 'fdsasaaa/caipiaowenzhang',
        'source_parent_evidence_ref' => '55e3d8982426976863613669ef0172112bf76eb5',
        'source_intake_mode' => 'public_release_transfer_canary',
    ];
    foreach ($expected as $field => $value) {
        if (($payload[$field] ?? null) !== $value) {
            transferTestFail('Draft field mismatch: ' . $field);
        }
    }
    if (array_key_exists('publish_at', $payload)) {
        transferTestFail('transfer canary Draft unexpectedly contains publish_at');
    }

    $bad = json_decode((string) file_get_contents($evidence), true);
    if (!is_array($bad)) {
        transferTestFail('cannot decode parent evidence fixture');
    }
    $bad['content_hash'] = str_repeat('0', 64);
    file_put_contents($badEvidence, json_encode($bad, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($ingest)
        . ' --revision=' . escapeshellarg($revision)
        . ' --parent-evidence=' . escapeshellarg($badEvidence)
        . ' --manifest=' . escapeshellarg($manifest)
        . ' --editorial-cluster-map=' . escapeshellarg($map)
        . ' --output=' . escapeshellarg($badDraft);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code === 0 || is_file($badDraft)) {
        transferTestFail('tampered parent evidence failed open');
    }

    fwrite(STDOUT, "[public-release-transfer-test] PASS safe_bundle=validated parent_body=absent cluster=applied lifecycle=draft_only\n");
} finally {
    foreach (glob($tmp . '/*') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmp);
}

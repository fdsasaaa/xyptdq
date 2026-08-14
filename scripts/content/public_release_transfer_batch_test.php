#!/usr/bin/env php
<?php
declare(strict_types=1);

function failTest(string $message): void
{
    fwrite(STDERR, '[transfer-batch-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

$root = dirname(__DIR__, 2);
$ingress = $root . '/content/ingress/public-release/CF50-20260813';
$batch = __DIR__ . '/ingest_public_release_transfer_batch.php';
$map = $root . '/content/seo_editorial_cluster_map_cf50.json';
$ids = [
    'LCM-CREATOR-cf50-20260813-011',
    'LCM-CREATOR-cf50-20260813-021',
    'LCM-CREATOR-cf50-20260813-031',
    'LCM-CREATOR-cf50-20260813-041',
    'LCM-CREATOR-cf50-20260813-046',
    'LCM-CREATOR-cf50-20260813-002',
    'LCM-CREATOR-cf50-20260813-012',
    'LCM-CREATOR-cf50-20260813-022',
    'LCM-CREATOR-cf50-20260813-032',
    'LCM-CREATOR-cf50-20260813-037',
    'LCM-CREATOR-cf50-20260813-049',
];
$tmp = sys_get_temp_dir() . '/xyptdq-wave1-transfer-' . getmypid();
if (!mkdir($tmp, 0750, true) && !is_dir($tmp)) {
    failTest('cannot create temp dir');
}
try {
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($batch)
        . ' --ingress-dir=' . escapeshellarg($ingress)
        . ' --parent-index=' . escapeshellarg($ingress . '/parent-identity-index.json')
        . ' --manifest=' . escapeshellarg($ingress . '/manifest.json')
        . ' --editorial-cluster-map=' . escapeshellarg($map)
        . ' --output-dir=' . escapeshellarg($tmp)
        . ' --article-ids=' . escapeshellarg(implode(',', $ids));
    $out = [];
    $exit = 0;
    exec($cmd . ' 2>&1', $out, $exit);
    if ($exit !== 0) {
        failTest('real wave1 transfer failed: ' . implode("\n", $out));
    }
    $files = glob($tmp . '/*.json') ?: [];
    if (count($files) !== count($ids)) {
        failTest('expected 11 Drafts, got ' . count($files));
    }
    foreach ($ids as $id) {
        $path = $tmp . '/' . $id . '.json';
        $draft = json_decode((string) file_get_contents($path), true);
        if (!is_array($draft)) {
            failTest('invalid Draft: ' . $id);
        }
        if (($draft['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $draft)) {
            failTest('Draft lifecycle violation: ' . $id);
        }
        if (($draft['site_category_key'] ?? null) !== 'tzjq' || (int) ($draft['catid'] ?? 0) !== 3) {
            failTest('category mismatch: ' . $id);
        }
        if (($draft['primary_seo_cluster_id'] ?? null) !== 'ffc_research') {
            failTest('Cluster mismatch: ' . $id);
        }
        if (($draft['source_revision_id'] ?? null) !== $id . ':public-r1') {
            failTest('revision provenance mismatch: ' . $id);
        }
    }
    fwrite(STDOUT, '[transfer-batch-test] PASS count=11 draft_only=YES category=tzjq cluster=ffc_research provenance=preserved' . PHP_EOL);
} finally {
    foreach (glob($tmp . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmp);
}

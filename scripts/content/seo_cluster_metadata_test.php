#!/usr/bin/env php
<?php
declare(strict_types=1);

$repoRoot = dirname(__DIR__, 2);
$converter = __DIR__ . '/convert_approved_to_draft.php';
$fixture = $repoRoot . '/content/ingress/smoke-batch2/LCM-IDEA-bf5a9864b004ae17.json';

function clusterTestFail(string $message): void
{
    fwrite(STDERR, '[seo-cluster-metadata-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function writeJson(string $path, array $payload): void
{
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($path, $json . PHP_EOL) === false) {
        clusterTestFail('cannot write test JSON: ' . $path);
    }
}

if (!is_file($fixture)) {
    clusterTestFail('fixture missing');
}
$base = json_decode((string) file_get_contents($fixture), true);
if (!is_array($base)) {
    clusterTestFail('fixture invalid');
}

$tmp = sys_get_temp_dir() . '/xyptdq-cluster-test-' . getmypid();
if (!mkdir($tmp, 0750, true) && !is_dir($tmp)) {
    clusterTestFail('cannot create temp directory');
}

try {
    $valid = $base;
    $valid['primary_seo_cluster_id'] = 'ssc';
    $valid['secondary_seo_cluster_ids'] = ['research_lab'];
    $validInput = $tmp . '/valid.json';
    $validDraft = $tmp . '/valid-draft.json';
    writeJson($validInput, $valid);

    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($validInput)
        . ' --output=' . escapeshellarg($validDraft);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code !== 0) {
        clusterTestFail('valid cluster conversion failed: ' . implode("\n", $out));
    }
    $draft = json_decode((string) file_get_contents($validDraft), true);
    if (!is_array($draft)) {
        clusterTestFail('valid draft invalid');
    }
    if (($draft['primary_seo_cluster_id'] ?? null) !== 'ssc') {
        clusterTestFail('primary SEO cluster not preserved');
    }
    if (($draft['secondary_seo_cluster_ids'] ?? null) !== ['research_lab']) {
        clusterTestFail('secondary SEO clusters not preserved');
    }
    if (($draft['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $draft)) {
        clusterTestFail('cluster metadata changed draft-only lifecycle');
    }

    $invalid = $base;
    $invalid['primary_seo_cluster_id'] = 'made_up_cluster';
    $invalid['secondary_seo_cluster_ids'] = [];
    $invalidInput = $tmp . '/invalid.json';
    $invalidDraft = $tmp . '/invalid-draft.json';
    writeJson($invalidInput, $invalid);
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($invalidInput)
        . ' --output=' . escapeshellarg($invalidDraft);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code === 0) {
        clusterTestFail('unknown SEO cluster was accepted');
    }
    if (is_file($invalidDraft)) {
        clusterTestFail('invalid SEO cluster created a draft');
    }

    $legacyInput = $tmp . '/legacy.json';
    $legacyDraft = $tmp . '/legacy-draft.json';
    writeJson($legacyInput, $base);
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($legacyInput)
        . ' --output=' . escapeshellarg($legacyDraft);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code !== 0) {
        clusterTestFail('legacy package without cluster metadata stopped working: ' . implode("\n", $out));
    }
    $legacyDraftData = json_decode((string) file_get_contents($legacyDraft), true);
    if (!is_array($legacyDraftData)) {
        clusterTestFail('legacy draft invalid');
    }
    if (array_key_exists('primary_seo_cluster_id', $legacyDraftData) || array_key_exists('secondary_seo_cluster_ids', $legacyDraftData)) {
        clusterTestFail('legacy package gained guessed cluster metadata');
    }
} finally {
    foreach (glob($tmp . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmp);
}

fwrite(STDOUT, "[seo-cluster-metadata-test] PASS valid=preserved invalid=rejected legacy=compatible publishing=untouched\n");

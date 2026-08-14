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

function runConverter(string $converter, string $input, string $output, ?string $editorialMap = null): array
{
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($input)
        . ' --output=' . escapeshellarg($output);
    if ($editorialMap !== null) {
        $cmd .= ' --editorial-cluster-map=' . escapeshellarg($editorialMap);
    }
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    return [$code, $out];
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

    [$code, $out] = runConverter($converter, $validInput, $validDraft);
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
    if (($draft['seo_cluster_assignment_source'] ?? null) !== 'package') {
        clusterTestFail('package SEO cluster assignment source not recorded');
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
    [$code, $out] = runConverter($converter, $invalidInput, $invalidDraft);
    if ($code === 0) {
        clusterTestFail('unknown SEO cluster was accepted');
    }
    if (is_file($invalidDraft)) {
        clusterTestFail('invalid SEO cluster created a draft');
    }

    $legacyInput = $tmp . '/legacy.json';
    $legacyDraft = $tmp . '/legacy-draft.json';
    writeJson($legacyInput, $base);
    [$code, $out] = runConverter($converter, $legacyInput, $legacyDraft);
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
    if (array_key_exists('seo_cluster_assignment_source', $legacyDraftData)) {
        clusterTestFail('legacy package gained an invented cluster assignment source');
    }

    $editorialMap = [
        'schema_version' => 1,
        'map_id' => 'TEST-BATCH-ffc-research',
        'batch_id' => 'TEST-BATCH',
        'article_id_prefix' => 'LCM-EDITORIAL-',
        'article_id_range' => [1, 2],
        'primary_seo_cluster_id' => 'ffc_research',
        'secondary_seo_cluster_ids' => [],
        'assignment_type' => 'editorial_batch_contract',
    ];
    $editorialMapPath = $tmp . '/editorial-map.json';
    writeJson($editorialMapPath, $editorialMap);

    $mapped = $base;
    $mapped['article_id'] = 'LCM-EDITORIAL-001';
    $mapped['creator_batch_id'] = 'TEST-BATCH';
    unset($mapped['primary_seo_cluster_id'], $mapped['secondary_seo_cluster_ids']);
    $mappedInput = $tmp . '/mapped.json';
    $mappedDraft = $tmp . '/mapped-draft.json';
    writeJson($mappedInput, $mapped);
    [$code, $out] = runConverter($converter, $mappedInput, $mappedDraft, $editorialMapPath);
    if ($code !== 0) {
        clusterTestFail('valid editorial-map conversion failed: ' . implode("\n", $out));
    }
    $mappedDraftData = json_decode((string) file_get_contents($mappedDraft), true);
    if (!is_array($mappedDraftData)) {
        clusterTestFail('mapped draft invalid');
    }
    if (($mappedDraftData['primary_seo_cluster_id'] ?? null) !== 'ffc_research') {
        clusterTestFail('editorial map primary cluster not applied');
    }
    if (($mappedDraftData['secondary_seo_cluster_ids'] ?? null) !== []) {
        clusterTestFail('editorial map secondary clusters not applied');
    }
    if (($mappedDraftData['seo_cluster_assignment_source'] ?? null) !== 'editorial_map:TEST-BATCH-ffc-research') {
        clusterTestFail('editorial map source not recorded');
    }
    if (($mappedDraftData['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $mappedDraftData)) {
        clusterTestFail('editorial map changed draft-only lifecycle');
    }

    $wrongBatch = $mapped;
    $wrongBatch['creator_batch_id'] = 'OTHER-BATCH';
    $wrongBatchInput = $tmp . '/wrong-batch.json';
    $wrongBatchDraft = $tmp . '/wrong-batch-draft.json';
    writeJson($wrongBatchInput, $wrongBatch);
    [$code, $out] = runConverter($converter, $wrongBatchInput, $wrongBatchDraft, $editorialMapPath);
    if ($code === 0 || is_file($wrongBatchDraft)) {
        clusterTestFail('editorial map accepted a package from the wrong batch');
    }

    $conflict = $mapped;
    $conflict['primary_seo_cluster_id'] = 'ssc';
    $conflict['secondary_seo_cluster_ids'] = [];
    $conflictInput = $tmp . '/conflict.json';
    $conflictDraft = $tmp . '/conflict-draft.json';
    writeJson($conflictInput, $conflict);
    [$code, $out] = runConverter($converter, $conflictInput, $conflictDraft, $editorialMapPath);
    if ($code === 0 || is_file($conflictDraft)) {
        clusterTestFail('editorial map conflict did not fail closed');
    }
} finally {
    foreach (glob($tmp . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmp);
}

fwrite(STDOUT, "[seo-cluster-metadata-test] PASS package=preserved editorial_map=applied conflicts=rejected legacy=compatible publishing=untouched\n");

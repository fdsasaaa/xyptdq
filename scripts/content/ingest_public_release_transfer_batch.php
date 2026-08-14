#!/usr/bin/env php
<?php
declare(strict_types=1);

function batchFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[public-release-transfer-batch] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function batchReadJson(string $path, string $label): array
{
    if (!is_file($path)) {
        throw new RuntimeException($label . ' file not found: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data) || json_last_error() !== JSON_ERROR_NONE) {
        throw new RuntimeException($label . ' invalid JSON: ' . json_last_error_msg());
    }
    return $data;
}

function batchWriteJson(string $path, array $data): void
{
    $json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($path, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary JSON: ' . $path);
    }
}

$options = getopt('', [
    'ingress-dir:',
    'parent-index:',
    'manifest:',
    'editorial-cluster-map:',
    'output-dir:',
    'article-ids:',
]);
foreach (['ingress-dir', 'parent-index', 'manifest', 'editorial-cluster-map', 'output-dir', 'article-ids'] as $required) {
    if (!isset($options[$required]) || trim((string) $options[$required]) === '') {
        batchFail('missing required --' . $required, 2);
    }
}

$ingressDir = rtrim((string) $options['ingress-dir'], DIRECTORY_SEPARATOR);
$parentIndexPath = (string) $options['parent-index'];
$manifestPath = (string) $options['manifest'];
$mapPath = (string) $options['editorial-cluster-map'];
$outputDir = rtrim((string) $options['output-dir'], DIRECTORY_SEPARATOR);
$requested = array_values(array_filter(array_map('trim', explode(',', (string) $options['article-ids'])), static fn($v) => $v !== ''));
if (!$requested || count($requested) !== count(array_unique($requested))) {
    batchFail('article-ids must contain unique non-empty IDs', 2);
}
if (preg_match('~(^|[\\/])scheduled([\\/]|$)~i', $outputDir) === 1) {
    batchFail('batch output must be Draft-only and may not target Scheduled', 3);
}
if (!is_dir($outputDir) && !mkdir($outputDir, 0750, true) && !is_dir($outputDir)) {
    batchFail('cannot create output directory', 3);
}

$created = [];
$tmpDir = sys_get_temp_dir() . '/xyptdq-transfer-batch-' . getmypid();
if (!mkdir($tmpDir, 0750, true) && !is_dir($tmpDir)) {
    batchFail('cannot create temporary directory', 3);
}

try {
    $index = batchReadJson($parentIndexPath, 'parent identity index');
    $manifest = batchReadJson($manifestPath, 'manifest');
    if ((int) ($index['schema_version'] ?? 0) !== 1 || ($index['evidence_kind'] ?? null) !== 'immutable_approved_parent_identity_index') {
        throw new RuntimeException('invalid parent identity index contract');
    }
    if (($index['contains_parent_body'] ?? null) !== false) {
        throw new RuntimeException('parent identity index must explicitly exclude parent body');
    }
    $sourceRepo = trim((string) ($index['source_repository'] ?? ''));
    $sourceRef = trim((string) ($index['source_ref'] ?? ''));
    if ($sourceRepo === '' || !preg_match('/^[0-9a-f]{40}$/', $sourceRef)) {
        throw new RuntimeException('parent identity source repository/ref is invalid');
    }
    if ((string) ($index['source_batch_id'] ?? '') !== (string) ($manifest['source_batch_id'] ?? '')) {
        throw new RuntimeException('parent identity batch does not match manifest');
    }

    $identityById = [];
    foreach (($index['articles'] ?? []) as $row) {
        if (!is_array($row)) {
            throw new RuntimeException('parent identity row must be an object');
        }
        if (array_key_exists('content', $row) || array_key_exists('body', $row)) {
            throw new RuntimeException('parent identity row must not contain parent body');
        }
        $id = trim((string) ($row['article_id'] ?? ''));
        if ($id === '' || isset($identityById[$id])) {
            throw new RuntimeException('parent identity article IDs must be unique');
        }
        $identityById[$id] = $row;
    }

    $manifestById = [];
    foreach (($manifest['articles'] ?? []) as $row) {
        if (!is_array($row)) {
            continue;
        }
        $id = trim((string) ($row['article_id'] ?? ''));
        if ($id !== '') {
            $manifestById[$id] = $row;
        }
    }

    $single = __DIR__ . '/ingest_public_release_transfer_canary.php';
    foreach ($requested as $articleId) {
        if (!isset($identityById[$articleId], $manifestById[$articleId])) {
            throw new RuntimeException('requested article missing from identity index or manifest: ' . $articleId);
        }
        $revisionPath = $ingressDir . DIRECTORY_SEPARATOR . $articleId . '.public-r1.json';
        if (!is_file($revisionPath)) {
            throw new RuntimeException('revision file missing from safe ingress: ' . $articleId);
        }
        $row = $identityById[$articleId];
        $evidence = $row;
        $evidence['schema_version'] = 1;
        $evidence['evidence_kind'] = 'immutable_approved_parent_identity';
        $evidence['source_repository'] = $sourceRepo;
        $evidence['source_ref'] = $sourceRef;
        $evidencePath = $tmpDir . DIRECTORY_SEPARATOR . $articleId . '.parent-evidence.json';
        batchWriteJson($evidencePath, $evidence);

        $outputPath = $outputDir . DIRECTORY_SEPARATOR . $articleId . '.json';
        if (is_file($outputPath)) {
            throw new RuntimeException('refusing to overwrite existing Draft: ' . $outputPath);
        }
        $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($single)
            . ' --revision=' . escapeshellarg($revisionPath)
            . ' --parent-evidence=' . escapeshellarg($evidencePath)
            . ' --manifest=' . escapeshellarg($manifestPath)
            . ' --editorial-cluster-map=' . escapeshellarg($mapPath)
            . ' --output=' . escapeshellarg($outputPath);
        $out = [];
        $exit = 0;
        exec($cmd . ' 2>&1', $out, $exit);
        if ($exit !== 0) {
            throw new RuntimeException('article intake failed for ' . $articleId . ': ' . implode("\n", $out));
        }
        $draft = batchReadJson($outputPath, 'generated Draft');
        if (($draft['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $draft)) {
            throw new RuntimeException('generated article is not Draft-only: ' . $articleId);
        }
        if (($draft['primary_seo_cluster_id'] ?? null) !== 'ffc_research') {
            throw new RuntimeException('explicit ffc_research Cluster missing: ' . $articleId);
        }
        $created[] = $outputPath;
    }

    fwrite(STDOUT, json_encode([
        'status' => 'transfer_batch_drafts_created',
        'count' => count($created),
        'article_ids' => $requested,
        'output_dir' => $outputDir,
        'lifecycle' => 'draft_only',
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
} catch (Throwable $e) {
    foreach ($created as $path) {
        @unlink($path);
    }
    batchFail($e->getMessage(), 1);
} finally {
    foreach (glob($tmpDir . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmpDir);
}

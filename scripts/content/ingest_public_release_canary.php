#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/public_release_package.php';

function canaryFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[public-release-canary] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function readJsonObjectForCanary(string $path, string $label): array
{
    if (!is_file($path)) {
        throw new RuntimeException($label . ' file not found: ' . $path);
    }
    $payload = json_decode((string) file_get_contents($path), true);
    if (!is_array($payload) || json_last_error() !== JSON_ERROR_NONE) {
        throw new RuntimeException($label . ' is invalid JSON: ' . json_last_error_msg());
    }
    return $payload;
}

function atomicCanaryJsonWrite(string $target, array $payload): void
{
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode final canary Draft');
    }
    $tmp = $target . '.tmp.' . getmypid();
    if (file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary canary Draft');
    }
    if (!rename($tmp, $target)) {
        @unlink($tmp);
        throw new RuntimeException('cannot atomically replace canary Draft');
    }
}

$options = getopt('', ['revision:', 'parent:', 'manifest:', 'editorial-cluster-map:', 'output:']);
$revisionPath = (string) ($options['revision'] ?? '');
$parentPath = (string) ($options['parent'] ?? '');
$manifestPath = (string) ($options['manifest'] ?? '');
$editorialMapPath = (string) ($options['editorial-cluster-map'] ?? '');
$outputPath = (string) ($options['output'] ?? '');

foreach ([
    'revision' => $revisionPath,
    'parent' => $parentPath,
    'manifest' => $manifestPath,
    'editorial-cluster-map' => $editorialMapPath,
    'output' => $outputPath,
] as $name => $value) {
    if ($value === '') {
        canaryFail('missing required --' . $name, 2);
    }
}

if (preg_match('~(^|[\\/])scheduled([\\/]|$)~i', $outputPath) === 1) {
    canaryFail('canary output must not target a Scheduled directory', 3);
}

try {
    $revision = readJsonObjectForCanary($revisionPath, 'revision');
    $parent = readJsonObjectForCanary($parentPath, 'parent');
    $manifest = readJsonObjectForCanary($manifestPath, 'manifest');

    $validation = xyptdq_validate_public_release_intake($revision, $parent, $manifest, 'canary');
    if (!$validation['passed']) {
        throw new RuntimeException('public-release intake validation failed: ' . implode('; ', $validation['errors']));
    }

    $converter = __DIR__ . '/convert_approved_to_draft.php';
    if (!is_file($converter)) {
        throw new RuntimeException('Approved-to-Draft converter is missing');
    }

    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($revisionPath)
        . ' --output=' . escapeshellarg($outputPath)
        . ' --editorial-cluster-map=' . escapeshellarg($editorialMapPath);
    $out = [];
    $exitCode = 0;
    exec($cmd . ' 2>&1', $out, $exitCode);
    if ($exitCode !== 0) {
        throw new RuntimeException('Draft conversion failed: ' . implode("\n", $out));
    }

    $draft = readJsonObjectForCanary($outputPath, 'generated Draft');
    if (($draft['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $draft)) {
        throw new RuntimeException('generated canary is not Draft-only');
    }
    if ((string) ($draft['source_article_id'] ?? '') !== (string) $revision['article_id']) {
        throw new RuntimeException('generated Draft source_article_id mismatch');
    }
    if (!hash_equals((string) ($draft['source_content_hash'] ?? ''), (string) $revision['content_hash'])) {
        throw new RuntimeException('generated Draft source_content_hash mismatch');
    }
    if ((string) ($draft['source_fingerprint'] ?? '') !== (string) $revision['fingerprint']) {
        throw new RuntimeException('generated Draft source_fingerprint mismatch');
    }

    $draft['source_revision_kind'] = (string) $revision['revision_kind'];
    $draft['source_revision_id'] = (string) $revision['revision_id'];
    $draft['source_release_revision'] = (int) $revision['release_revision'];
    $draft['source_batch_id'] = (string) $revision['source_batch_id'];
    $draft['source_creator_batch_id'] = (string) $revision['creator_batch_id'];
    $draft['source_parent_content_hash'] = (string) $revision['parent_content_hash'];
    $draft['source_parent_fingerprint'] = (string) $revision['parent_fingerprint'];
    $draft['source_public_release_reviewed_at'] = (string) $revision['public_release_review']['reviewed_at'];
    $draft['source_public_release_review_contract'] = (string) $revision['public_release_review']['review_contract'];
    $draft['source_intake_mode'] = 'public_release_canary';
    atomicCanaryJsonWrite($outputPath, $draft);

    fwrite(STDOUT, json_encode([
        'status' => 'canary_draft_created',
        'article_key' => $draft['article_key'] ?? null,
        'source_article_id' => $draft['source_article_id'],
        'source_revision_id' => $draft['source_revision_id'],
        'source_batch_id' => $draft['source_batch_id'],
        'site_category_key' => $draft['site_category_key'] ?? null,
        'primary_seo_cluster_id' => $draft['primary_seo_cluster_id'] ?? null,
        'seo_cluster_assignment_source' => $draft['seo_cluster_assignment_source'] ?? null,
        'publication_state' => $draft['publication_state'],
        'output' => $outputPath,
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
} catch (Throwable $e) {
    @unlink($outputPath);
    canaryFail($e->getMessage(), 1);
}

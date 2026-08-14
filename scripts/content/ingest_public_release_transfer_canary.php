#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/public_release_package.php';

function transferFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[public-release-transfer] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function transferReadJson(string $path, string $label): array
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

function transferAtomicWrite(string $target, array $payload): void
{
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode final transfer Draft');
    }
    $tmp = $target . '.tmp.' . getmypid();
    if (file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary transfer Draft');
    }
    if (!rename($tmp, $target)) {
        @unlink($tmp);
        throw new RuntimeException('cannot atomically replace transfer Draft');
    }
}

function validateParentEvidence(array $revision, array $evidence): array
{
    $errors = [];
    if ((int) ($evidence['schema_version'] ?? 0) !== 1) {
        $errors[] = 'parent evidence schema_version must be 1';
    }
    if (($evidence['evidence_kind'] ?? null) !== 'immutable_approved_parent_identity') {
        $errors[] = 'parent evidence kind must be immutable_approved_parent_identity';
    }
    if (!preg_match('/^[0-9a-f]{40}$/', (string) ($evidence['source_ref'] ?? ''))) {
        $errors[] = 'parent evidence source_ref must be a 40-character commit SHA';
    }
    if (trim((string) ($evidence['source_repository'] ?? '')) === '') {
        $errors[] = 'parent evidence source_repository is required';
    }
    if (trim((string) ($evidence['parent_path'] ?? '')) === '') {
        $errors[] = 'parent evidence parent_path is required';
    }

    $articleId = trim((string) ($revision['article_id'] ?? ''));
    if ($articleId === '' || $articleId !== trim((string) ($evidence['article_id'] ?? ''))) {
        $errors[] = 'parent evidence article_id mismatch';
    }
    $parentHash = strtolower(trim((string) ($evidence['content_hash'] ?? '')));
    if (!preg_match('/^[0-9a-f]{64}$/', $parentHash)) {
        $errors[] = 'parent evidence content_hash must be SHA-256';
    }
    if ($parentHash === '' || strtolower(trim((string) ($revision['parent_content_hash'] ?? ''))) !== $parentHash) {
        $errors[] = 'revision parent_content_hash does not match parent evidence';
    }
    $parentFingerprint = trim((string) ($evidence['fingerprint'] ?? ''));
    if ($parentFingerprint === '' || !hash_equals($parentFingerprint, (string) ($revision['parent_fingerprint'] ?? ''))) {
        $errors[] = 'revision parent_fingerprint does not match parent evidence';
    }
    if (strtolower(trim((string) ($revision['content_hash'] ?? ''))) === $parentHash) {
        $errors[] = 'public-release revision must change content_hash';
    }

    foreach (['slug', 'primary_keyword', 'site_category_key', 'content_type'] as $field) {
        if (($revision[$field] ?? null) !== ($evidence[$field] ?? null)) {
            $errors[] = 'revision must preserve parent evidence ' . $field;
        }
    }

    $parentBatch = trim((string) ($evidence['creator_batch_id'] ?? ''));
    if ($parentBatch === '') {
        $errors[] = 'parent evidence creator_batch_id is required';
    }
    if (trim((string) ($revision['creator_batch_id'] ?? '')) !== $parentBatch) {
        $errors[] = 'revision creator_batch_id does not match parent evidence';
    }
    if (trim((string) ($revision['source_batch_id'] ?? '')) !== $parentBatch) {
        $errors[] = 'revision source_batch_id does not match parent evidence';
    }
    return $errors;
}

function validateTransfer(array $revision, array $evidence, array $manifest): array
{
    $errors = [];
    $revisionValidation = xyptdq_validate_approved_package($revision);
    if (!$revisionValidation['passed']) {
        foreach ($revisionValidation['errors'] as $error) {
            $errors[] = 'revision: ' . $error;
        }
    }
    foreach (validateParentEvidence($revision, $evidence) as $error) {
        $errors[] = $error;
    }

    $articleId = trim((string) ($revision['article_id'] ?? ''));
    $releaseRevision = $revision['release_revision'] ?? null;
    if (($revision['revision_kind'] ?? null) !== 'website_public_release') {
        $errors[] = 'revision_kind must be website_public_release';
    }
    if (!is_int($releaseRevision) || $releaseRevision < 1) {
        $errors[] = 'release_revision must be a positive integer';
    } elseif ((string) ($revision['revision_id'] ?? '') !== $articleId . ':public-r' . $releaseRevision) {
        $errors[] = 'revision_id does not match article_id/release_revision';
    }
    if (strtolower(trim((string) ($revision['content_format'] ?? ''))) !== 'html') {
        $errors[] = 'content_format must be explicit html';
    }

    $review = $revision['public_release_review'] ?? null;
    if (!is_array($review) || ($review['status'] ?? null) !== 'approved') {
        $errors[] = 'public_release_review.status must be approved';
    } elseif (trim((string) ($review['reviewed_at'] ?? '')) === '' || trim((string) ($review['review_contract'] ?? '')) === '') {
        $errors[] = 'public_release_review metadata is incomplete';
    }

    $fingerprint = trim((string) ($revision['fingerprint'] ?? ''));
    if ($fingerprint === '' || !hash_equals(xyptdq_public_release_expected_fingerprint($revision), $fingerprint)) {
        $errors[] = 'public-release fingerprint mismatch';
    }

    $sourceBatch = trim((string) ($revision['source_batch_id'] ?? ''));
    if ((int) ($manifest['schema_version'] ?? 0) !== 1) {
        $errors[] = 'manifest schema_version must be 1';
    }
    if (($manifest['revision_kind'] ?? null) !== 'website_public_release') {
        $errors[] = 'manifest revision_kind must be website_public_release';
    }
    if ((string) ($manifest['source_batch_id'] ?? '') !== $sourceBatch) {
        $errors[] = 'manifest source_batch_id does not match revision';
    }
    if (($manifest['canary_ingestion_allowed'] ?? null) !== true) {
        $errors[] = 'manifest does not allow canary ingestion';
    }

    $manifestMatch = false;
    $articles = $manifest['articles'] ?? null;
    if (!is_array($articles)) {
        $errors[] = 'manifest articles must be an array';
    } else {
        foreach ($articles as $row) {
            if (!is_array($row) || (string) ($row['article_id'] ?? '') !== $articleId) {
                continue;
            }
            if (
                (string) ($row['revision_id'] ?? '') === (string) ($revision['revision_id'] ?? '')
                && strtolower((string) ($row['content_hash'] ?? '')) === strtolower((string) ($revision['content_hash'] ?? ''))
                && (string) ($row['fingerprint'] ?? '') === $fingerprint
            ) {
                $manifestMatch = true;
                break;
            }
        }
        if (!$manifestMatch) {
            $errors[] = 'manifest does not contain the exact revision identity';
        }
    }

    return ['passed' => count($errors) === 0, 'errors' => $errors, 'manifest_match' => $manifestMatch];
}

$options = getopt('', ['revision:', 'parent-evidence:', 'manifest:', 'editorial-cluster-map:', 'output:']);
$revisionPath = (string) ($options['revision'] ?? '');
$evidencePath = (string) ($options['parent-evidence'] ?? '');
$manifestPath = (string) ($options['manifest'] ?? '');
$mapPath = (string) ($options['editorial-cluster-map'] ?? '');
$outputPath = (string) ($options['output'] ?? '');
foreach (['revision' => $revisionPath, 'parent-evidence' => $evidencePath, 'manifest' => $manifestPath, 'editorial-cluster-map' => $mapPath, 'output' => $outputPath] as $name => $value) {
    if ($value === '') {
        transferFail('missing required --' . $name, 2);
    }
}
if (preg_match('~(^|[\\/])scheduled([\\/]|$)~i', $outputPath) === 1) {
    transferFail('transfer output must not target a Scheduled directory', 3);
}

try {
    $revision = transferReadJson($revisionPath, 'revision');
    $evidence = transferReadJson($evidencePath, 'parent evidence');
    $manifest = transferReadJson($manifestPath, 'manifest');
    $validation = validateTransfer($revision, $evidence, $manifest);
    if (!$validation['passed']) {
        throw new RuntimeException('public-release transfer validation failed: ' . implode('; ', $validation['errors']));
    }

    $converter = __DIR__ . '/convert_approved_to_draft.php';
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($revisionPath)
        . ' --output=' . escapeshellarg($outputPath)
        . ' --editorial-cluster-map=' . escapeshellarg($mapPath);
    $out = [];
    $exitCode = 0;
    exec($cmd . ' 2>&1', $out, $exitCode);
    if ($exitCode !== 0) {
        throw new RuntimeException('Draft conversion failed: ' . implode("\n", $out));
    }

    $draft = transferReadJson($outputPath, 'generated Draft');
    if (($draft['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $draft)) {
        throw new RuntimeException('generated transfer canary is not Draft-only');
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
    $draft['source_parent_evidence_kind'] = (string) $evidence['evidence_kind'];
    $draft['source_parent_evidence_repository'] = (string) $evidence['source_repository'];
    $draft['source_parent_evidence_ref'] = (string) $evidence['source_ref'];
    $draft['source_public_release_reviewed_at'] = (string) $revision['public_release_review']['reviewed_at'];
    $draft['source_public_release_review_contract'] = (string) $revision['public_release_review']['review_contract'];
    $draft['source_intake_mode'] = 'public_release_transfer_canary';
    transferAtomicWrite($outputPath, $draft);

    fwrite(STDOUT, json_encode([
        'status' => 'transfer_canary_draft_created',
        'source_article_id' => $draft['source_article_id'],
        'source_revision_id' => $draft['source_revision_id'],
        'source_batch_id' => $draft['source_batch_id'],
        'site_category_key' => $draft['site_category_key'] ?? null,
        'primary_seo_cluster_id' => $draft['primary_seo_cluster_id'] ?? null,
        'publication_state' => $draft['publication_state'],
        'output' => $outputPath,
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
} catch (Throwable $e) {
    @unlink($outputPath);
    transferFail($e->getMessage(), 1);
}

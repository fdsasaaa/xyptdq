#!/usr/bin/env php
<?php
/**
 * Validated public-release -> Draft converter for incremental website intake.
 *
 * Modes:
 * - terminal_cf50: explicit 45/50 CF50 waiting-state exception. Uses the
 *   manifest canary contract plus website policy guards; frozen final-five IDs
 *   remain forbidden.
 * - batch: ordinary future formal batches. Requires manifest status=complete
 *   and website_batch_ingestion_allowed=true through the canonical validator.
 *
 * An editorial Cluster map is optional. A map is applied only when its explicit
 * batch_id equals the revision source_batch_id. A mismatched map is ignored so
 * it can never bleed one batch's editorial decision into another. Without a
 * matching map, explicit revision Cluster metadata is validated by the normal
 * converter; otherwise the Draft may remain unassigned, which the Cluster
 * registry permits. Cluster assignment is never guessed from title text.
 *
 * This script never creates publish_at, Scheduled state, CMS content, or
 * Publisher state.
 */
declare(strict_types=1);

require __DIR__ . '/lib/public_release_package.php';

function intakeDraftFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[public-release-draft] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function intakeDraftReadJson(string $path, string $label): array
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

function intakeDraftAtomicWrite(string $path, array $data): void
{
    $dir = dirname($path);
    if (!is_dir($dir) && !mkdir($dir, 0750, true) && !is_dir($dir)) {
        throw new RuntimeException('cannot create Draft directory: ' . $dir);
    }
    $json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode final Draft');
    }
    $tmp = $path . '.tmp.' . getmypid();
    if (file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary Draft');
    }
    @chmod($tmp, 0640);
    if (!rename($tmp, $path)) {
        @unlink($tmp);
        throw new RuntimeException('cannot atomically replace Draft');
    }
}

$options = getopt('', [
    'revision:', 'parent:', 'manifest:', 'inventory-policy:',
    'editorial-cluster-map::', 'output:', 'mode:'
]);
foreach (['revision','parent','manifest','inventory-policy','output','mode'] as $name) {
    if (!isset($options[$name]) || trim((string) $options[$name]) === '') {
        intakeDraftFail('missing required --' . $name, 2);
    }
}

$revisionPath = (string) $options['revision'];
$parentPath = (string) $options['parent'];
$manifestPath = (string) $options['manifest'];
$policyPath = (string) $options['inventory-policy'];
$editorialMapPath = trim((string) ($options['editorial-cluster-map'] ?? ''));
$outputPath = (string) $options['output'];
$mode = (string) $options['mode'];

if (!in_array($mode, ['terminal_cf50', 'batch'], true)) {
    intakeDraftFail('mode must be terminal_cf50 or batch', 2);
}
if (preg_match('~(^|[\\/])scheduled([\\/]|$)~i', $outputPath) === 1) {
    intakeDraftFail('Draft output must not target Scheduled', 3);
}
if (is_file($outputPath)) {
    intakeDraftFail('refusing to overwrite existing Draft', 4);
}

try {
    $revision = intakeDraftReadJson($revisionPath, 'revision');
    $parent = intakeDraftReadJson($parentPath, 'parent');
    $manifest = intakeDraftReadJson($manifestPath, 'manifest');
    $policy = intakeDraftReadJson($policyPath, 'inventory policy');

    if ($mode === 'terminal_cf50') {
        $cf50 = $policy['cf50_terminal_baseline'] ?? null;
        if (!is_array($cf50)) {
            throw new RuntimeException('CF50 terminal baseline policy missing');
        }
        $batchId = (string) ($manifest['source_batch_id'] ?? '');
        if ($batchId === '' || $batchId !== (string) ($cf50['source_batch_id'] ?? '')) {
            throw new RuntimeException('terminal_cf50 manifest does not match policy batch');
        }
        if (($cf50['release_authorized'] ?? null) !== false) {
            throw new RuntimeException('terminal_cf50 exception is only valid while final-five release remains unauthorized');
        }
        $articles = $manifest['articles'] ?? null;
        if (!is_array($articles) || count($articles) !== (int) ($cf50['website_ready_public_r1_count'] ?? 0)) {
            throw new RuntimeException('terminal_cf50 manifest count does not match explicit 45-public-r1 waiting state');
        }
        $articleId = (string) ($revision['article_id'] ?? '');
        $frozen = $cf50['final5_frozen_pending_issue_264'] ?? [];
        if (!is_array($frozen) || in_array($articleId, $frozen, true)) {
            throw new RuntimeException('terminal_cf50 article is frozen behind Issue #264');
        }
        $validation = xyptdq_validate_public_release_intake($revision, $parent, $manifest, 'canary');
    } else {
        $validation = xyptdq_validate_public_release_intake($revision, $parent, $manifest, 'batch');
    }
    if (!$validation['passed']) {
        throw new RuntimeException('public-release validation failed: ' . implode('; ', $validation['errors']));
    }

    if ($editorialMapPath !== '') {
        if (!is_file($editorialMapPath)) {
            throw new RuntimeException('editorial Cluster map not found');
        }
        $editorialMap = intakeDraftReadJson($editorialMapPath, 'editorial Cluster map');
        $mapBatchId = trim((string) ($editorialMap['batch_id'] ?? ''));
        $revisionBatchId = trim((string) ($revision['source_batch_id'] ?? ''));
        if ($mapBatchId === '' || $mapBatchId !== $revisionBatchId) {
            $editorialMapPath = '';
        }
    }
    if ($mode === 'terminal_cf50' && $editorialMapPath === '') {
        throw new RuntimeException('terminal_cf50 requires its matching explicit editorial Cluster map');
    }

    $converter = __DIR__ . '/convert_approved_to_draft.php';
    if (!is_file($converter)) {
        throw new RuntimeException('Draft converter missing');
    }
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
        . ' --input=' . escapeshellarg($revisionPath)
        . ' --output=' . escapeshellarg($outputPath);
    if ($editorialMapPath !== '') {
        $cmd .= ' --editorial-cluster-map=' . escapeshellarg($editorialMapPath);
    }
    $out = [];
    $exit = 0;
    exec($cmd . ' 2>&1', $out, $exit);
    if ($exit !== 0) {
        throw new RuntimeException('Draft conversion failed: ' . implode("\n", $out));
    }

    $draft = intakeDraftReadJson($outputPath, 'generated Draft');
    if (($draft['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $draft)) {
        throw new RuntimeException('generated object is not Draft-only');
    }
    if ((string) ($draft['source_article_id'] ?? '') !== (string) ($revision['article_id'] ?? '')) {
        throw new RuntimeException('Draft source_article_id mismatch');
    }
    if (!hash_equals((string) ($draft['source_content_hash'] ?? ''), (string) ($revision['content_hash'] ?? ''))) {
        throw new RuntimeException('Draft source_content_hash mismatch');
    }
    if ((string) ($draft['source_fingerprint'] ?? '') !== (string) ($revision['fingerprint'] ?? '')) {
        throw new RuntimeException('Draft source_fingerprint mismatch');
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
    $draft['source_intake_mode'] = $mode === 'terminal_cf50' ? 'inventory_terminal_cf50' : 'inventory_formal_batch';
    intakeDraftAtomicWrite($outputPath, $draft);

    fwrite(STDOUT, json_encode([
        'status' => 'draft_created',
        'mode' => $mode,
        'article_id' => $revision['article_id'],
        'revision_id' => $revision['revision_id'],
        'publication_state' => $draft['publication_state'],
        'primary_seo_cluster_id' => $draft['primary_seo_cluster_id'] ?? null,
        'cluster_assignment_source' => $draft['seo_cluster_assignment_source'] ?? null,
        'output' => $outputPath,
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
} catch (Throwable $e) {
    @unlink($outputPath);
    intakeDraftFail($e->getMessage(), 1);
}

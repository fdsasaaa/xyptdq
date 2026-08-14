<?php
/**
 * Website-side validation for immutable Approved parent + reviewed public-release revision.
 * This library is read-only and never writes CMS, Draft, Scheduled, or Publisher state.
 */
declare(strict_types=1);

require_once __DIR__ . '/approved_package.php';

function xyptdq_public_release_expected_fingerprint(array $revision): string
{
    $identity = [
        'article_id' => (string) ($revision['article_id'] ?? ''),
        'revision_id' => (string) ($revision['revision_id'] ?? ''),
        'revision_kind' => (string) ($revision['revision_kind'] ?? ''),
        'release_revision' => (int) ($revision['release_revision'] ?? 0),
        'parent_content_hash' => (string) ($revision['parent_content_hash'] ?? ''),
        'parent_fingerprint' => (string) ($revision['parent_fingerprint'] ?? ''),
        'content_hash' => (string) ($revision['content_hash'] ?? ''),
        'slug' => (string) ($revision['slug'] ?? ''),
        'primary_keyword' => (string) ($revision['primary_keyword'] ?? ''),
    ];
    ksort($identity, SORT_STRING);
    $json = json_encode($identity, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode public-release fingerprint identity');
    }
    return hash('sha256', $json);
}

function xyptdq_validate_public_release_intake(array $revision, array $parent, array $manifest, string $mode = 'canary'): array
{
    $errors = [];
    $warnings = [];

    if (!in_array($mode, ['canary', 'batch'], true)) {
        $errors[] = 'mode must be canary or batch';
    }

    $parentValidation = xyptdq_validate_approved_package($parent);
    if (!$parentValidation['passed']) {
        foreach ($parentValidation['errors'] as $error) {
            $errors[] = 'parent: ' . $error;
        }
    }
    $revisionValidation = xyptdq_validate_approved_package($revision);
    if (!$revisionValidation['passed']) {
        foreach ($revisionValidation['errors'] as $error) {
            $errors[] = 'revision: ' . $error;
        }
    }
    foreach ($parentValidation['warnings'] as $warning) {
        $warnings[] = 'parent: ' . $warning;
    }
    foreach ($revisionValidation['warnings'] as $warning) {
        $warnings[] = 'revision: ' . $warning;
    }

    $articleId = trim((string) ($revision['article_id'] ?? ''));
    $parentArticleId = trim((string) ($parent['article_id'] ?? ''));
    if ($articleId === '' || $articleId !== $parentArticleId) {
        $errors[] = 'revision article_id must match immutable parent';
    }

    if (($revision['revision_kind'] ?? null) !== 'website_public_release') {
        $errors[] = 'revision_kind must be website_public_release';
    }
    $releaseRevision = $revision['release_revision'] ?? null;
    if (!is_int($releaseRevision) || $releaseRevision < 1) {
        $errors[] = 'release_revision must be a positive integer';
    } elseif ((string) ($revision['revision_id'] ?? '') !== $articleId . ':public-r' . $releaseRevision) {
        $errors[] = 'revision_id does not match article_id/release_revision';
    }

    $parentHash = strtolower(trim((string) ($parent['content_hash'] ?? '')));
    $revisionHash = strtolower(trim((string) ($revision['content_hash'] ?? '')));
    if ($parentHash === '' || strtolower(trim((string) ($revision['parent_content_hash'] ?? ''))) !== $parentHash) {
        $errors[] = 'parent_content_hash does not match immutable parent';
    }
    if ((string) ($revision['parent_fingerprint'] ?? '') !== (string) ($parent['fingerprint'] ?? '')) {
        $errors[] = 'parent_fingerprint does not match immutable parent';
    }
    if ($revisionHash === '' || $revisionHash === $parentHash) {
        $errors[] = 'public-release revision must have a changed content_hash';
    }

    foreach (['slug', 'primary_keyword', 'site_category_key', 'content_type'] as $field) {
        if (($revision[$field] ?? null) !== ($parent[$field] ?? null)) {
            $errors[] = 'revision must preserve parent ' . $field;
        }
    }

    $parentBatch = trim((string) ($parent['creator_batch_id'] ?? ''));
    $creatorBatch = trim((string) ($revision['creator_batch_id'] ?? ''));
    $sourceBatch = trim((string) ($revision['source_batch_id'] ?? ''));
    if ($parentBatch === '' || $creatorBatch !== $parentBatch) {
        $errors[] = 'creator_batch_id must be preserved from immutable parent';
    }
    if ($sourceBatch === '' || $sourceBatch !== $parentBatch) {
        $errors[] = 'source_batch_id must match parent creator_batch_id';
    }

    if (strtolower(trim((string) ($revision['content_format'] ?? ''))) !== 'html') {
        $errors[] = 'content_format must be explicit html';
    }

    $review = $revision['public_release_review'] ?? null;
    if (!is_array($review) || ($review['status'] ?? null) !== 'approved') {
        $errors[] = 'public_release_review.status must be approved';
    } else {
        if (trim((string) ($review['reviewed_at'] ?? '')) === '') {
            $errors[] = 'public_release_review.reviewed_at is required';
        }
        if (trim((string) ($review['review_contract'] ?? '')) === '') {
            $errors[] = 'public_release_review.review_contract is required';
        }
    }

    $fingerprint = trim((string) ($revision['fingerprint'] ?? ''));
    if ($fingerprint === '' || !hash_equals(xyptdq_public_release_expected_fingerprint($revision), $fingerprint)) {
        $errors[] = 'public-release fingerprint mismatch';
    }

    if ((int) ($manifest['schema_version'] ?? 0) !== 1) {
        $errors[] = 'manifest schema_version must be 1';
    }
    if (($manifest['revision_kind'] ?? null) !== 'website_public_release') {
        $errors[] = 'manifest revision_kind must be website_public_release';
    }
    if ((string) ($manifest['source_batch_id'] ?? '') !== $sourceBatch) {
        $errors[] = 'manifest source_batch_id does not match revision';
    }

    if ($mode === 'canary' && (($manifest['canary_ingestion_allowed'] ?? null) !== true)) {
        $errors[] = 'manifest does not allow canary ingestion';
    }
    if ($mode === 'batch') {
        if (($manifest['status'] ?? null) !== 'complete') {
            $errors[] = 'batch ingestion requires manifest status=complete';
        }
        if (($manifest['website_batch_ingestion_allowed'] ?? null) !== true) {
            $errors[] = 'manifest does not allow full batch ingestion';
        }
    }

    $articles = $manifest['articles'] ?? null;
    $manifestMatch = false;
    if (!is_array($articles)) {
        $errors[] = 'manifest articles must be an array';
    } else {
        foreach ($articles as $row) {
            if (!is_array($row) || (string) ($row['article_id'] ?? '') !== $articleId) {
                continue;
            }
            if (
                (string) ($row['revision_id'] ?? '') === (string) ($revision['revision_id'] ?? '')
                && strtolower((string) ($row['content_hash'] ?? '')) === $revisionHash
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

    return [
        'passed' => count($errors) === 0,
        'errors' => $errors,
        'warnings' => $warnings,
        'article_id' => $articleId,
        'revision_id' => (string) ($revision['revision_id'] ?? ''),
        'source_batch_id' => $sourceBatch,
        'mode' => $mode,
        'manifest_match' => $manifestMatch,
    ];
}

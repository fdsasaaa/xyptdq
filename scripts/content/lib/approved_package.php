<?php
/**
 * Shared validation for caipiaowenzhang Approved Packages.
 *
 * This library intentionally does not write the CMS database.
 */
declare(strict_types=1);

function xyptdq_validate_approved_package(array $package): array
{
    $errors = [];
    $warnings = [];
    $required = [
        'article_id', 'title', 'slug', 'meta_description', 'primary_keyword',
        'search_intent', 'content', 'category', 'rule_refs', 'source_refs', 'status'
    ];

    foreach ($required as $field) {
        if (!array_key_exists($field, $package)) {
            $errors[] = 'missing required field: ' . $field;
            continue;
        }
        if (is_string($package[$field]) && trim($package[$field]) === '') {
            $errors[] = 'empty required field: ' . $field;
        }
    }

    if (($package['status'] ?? null) !== 'approved') {
        $errors[] = 'status must be approved';
    }

    foreach (['rule_refs', 'source_refs'] as $field) {
        if (isset($package[$field]) && !is_array($package[$field])) {
            $errors[] = $field . ' must be an array';
        }
    }

    if (isset($package['secondary_keywords']) && !is_array($package['secondary_keywords'])) {
        $errors[] = 'secondary_keywords must be an array';
    }
    if (isset($package['tags']) && !is_array($package['tags'])) {
        $errors[] = 'tags must be an array';
    }
    if (isset($package['internal_links']) && !is_array($package['internal_links'])) {
        $errors[] = 'internal_links must be an array';
    }

    $primaryCluster = trim((string) ($package['primary_seo_cluster_id'] ?? ''));
    if (array_key_exists('primary_seo_cluster_id', $package) && $primaryCluster === '') {
        $errors[] = 'primary_seo_cluster_id must be a non-empty string when present';
    }
    $secondaryClusters = $package['secondary_seo_cluster_ids'] ?? [];
    if (!is_array($secondaryClusters)) {
        $errors[] = 'secondary_seo_cluster_ids must be an array';
        $secondaryClusters = [];
    }
    foreach ($secondaryClusters as $clusterId) {
        if (!is_string($clusterId) || trim($clusterId) === '') {
            $errors[] = 'secondary_seo_cluster_ids must contain non-empty strings';
            break;
        }
    }
    if ($secondaryClusters && $primaryCluster === '') {
        $errors[] = 'secondary_seo_cluster_ids require primary_seo_cluster_id';
    }
    if (count($secondaryClusters) !== count(array_unique($secondaryClusters))) {
        $errors[] = 'secondary_seo_cluster_ids must not contain duplicates';
    }
    if ($primaryCluster !== '' && in_array($primaryCluster, $secondaryClusters, true)) {
        $errors[] = 'primary_seo_cluster_id must not repeat in secondary_seo_cluster_ids';
    }

    $articleId = (string) ($package['article_id'] ?? '');
    if ($articleId !== '' && preg_match('/^[A-Za-z0-9._:-]+$/', $articleId) !== 1) {
        $errors[] = 'article_id contains unsupported characters';
    }

    $slug = (string) ($package['slug'] ?? '');
    if ($slug !== '' && (strpos($slug, "\n") !== false || strpos($slug, "\r") !== false || strpos($slug, '/') !== false)) {
        $errors[] = 'slug must be a single path segment';
    }

    $content = (string) ($package['content'] ?? '');
    if ($content !== '' && mb_strlen(trim($content), 'UTF-8') < 200) {
        $warnings[] = 'content is unusually short (<200 characters)';
    }

    if (isset($package['content_hash']) && trim((string) $package['content_hash']) !== '') {
        $expected = strtolower(trim((string) $package['content_hash']));
        $actual = hash('sha256', $content);
        if (!hash_equals($expected, $actual)) {
            $errors[] = 'content_hash does not match content';
        }
    } else {
        $warnings[] = 'content_hash is absent; integrity is weaker';
    }

    if (empty($package['fingerprint'])) {
        $warnings[] = 'fingerprint is absent; publication-memory linkage is weaker';
    }

    $caseScope = $package['case_scope'] ?? 'mechanics_only';
    if (!in_array($caseScope, ['mechanics_only', 'economics'], true)) {
        $errors[] = 'case_scope must be mechanics_only or economics';
    }

    return [
        'passed' => count($errors) === 0,
        'errors' => $errors,
        'warnings' => $warnings,
    ];
}

function xyptdq_read_package_file(string $path): array
{
    if (!is_file($path)) {
        throw new RuntimeException('package file not found: ' . $path);
    }
    $raw = file_get_contents($path);
    if ($raw === false) {
        throw new RuntimeException('unable to read package file: ' . $path);
    }
    $payload = json_decode($raw, true);
    if (!is_array($payload)) {
        throw new RuntimeException('package is not a valid JSON object: ' . json_last_error_msg());
    }
    return $payload;
}

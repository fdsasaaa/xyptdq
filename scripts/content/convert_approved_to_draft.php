#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/approved_package.php';

function draftFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[approved-to-draft] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function loadCategoryMap(string $path): array
{
    if (!is_file($path)) {
        throw new RuntimeException('category map not found: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data) || !isset($data['categories']) || !is_array($data['categories'])) {
        throw new RuntimeException('invalid category map');
    }
    return $data;
}

function loadClusterRegistry(string $path): array
{
    if (!is_file($path)) {
        throw new RuntimeException('SEO cluster registry not found: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data) || !isset($data['clusters']) || !is_array($data['clusters'])) {
        throw new RuntimeException('invalid SEO cluster registry');
    }
    $carrierKey = trim((string) ($data['article_carrier']['site_category_key'] ?? ''));
    if ($carrierKey === '') {
        throw new RuntimeException('SEO cluster registry article carrier is missing');
    }
    $ids = [];
    foreach ($data['clusters'] as $row) {
        $clusterId = trim((string) ($row['cluster_id'] ?? ''));
        if ($clusterId === '' || isset($ids[$clusterId])) {
            throw new RuntimeException('SEO cluster registry contains an invalid or duplicate cluster_id');
        }
        $ids[$clusterId] = true;
    }
    if (!$ids) {
        throw new RuntimeException('SEO cluster registry contains no clusters');
    }
    return ['carrier_key' => $carrierKey, 'ids' => $ids];
}

function loadEditorialClusterMap(string $path): array
{
    if (!is_file($path)) {
        throw new RuntimeException('editorial SEO cluster map not found: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data) || (int) ($data['schema_version'] ?? 0) !== 1) {
        throw new RuntimeException('invalid editorial SEO cluster map');
    }
    foreach (['map_id', 'batch_id', 'article_id_prefix', 'primary_seo_cluster_id', 'assignment_type'] as $field) {
        if (trim((string) ($data[$field] ?? '')) === '') {
            throw new RuntimeException('editorial SEO cluster map missing ' . $field);
        }
    }
    if ((string) $data['assignment_type'] !== 'editorial_batch_contract') {
        throw new RuntimeException('editorial SEO cluster map must use assignment_type=editorial_batch_contract');
    }
    $range = $data['article_id_range'] ?? null;
    if (!is_array($range) || count($range) !== 2 || (int) $range[0] <= 0 || (int) $range[1] < (int) $range[0]) {
        throw new RuntimeException('editorial SEO cluster map has invalid article_id_range');
    }
    $secondary = $data['secondary_seo_cluster_ids'] ?? [];
    if (!is_array($secondary)) {
        throw new RuntimeException('editorial SEO cluster map secondary_seo_cluster_ids must be an array');
    }
    return $data;
}

function applyEditorialClusterMap(array $package, array $map): array
{
    $articleId = trim((string) ($package['article_id'] ?? ''));
    $batchId = trim((string) ($package['creator_batch_id'] ?? $package['batch_id'] ?? ''));
    $expectedBatch = trim((string) $map['batch_id']);
    if ($batchId === '' || $batchId !== $expectedBatch) {
        throw new RuntimeException('Approved Package does not match editorial map batch_id');
    }

    $prefix = trim((string) $map['article_id_prefix']);
    if (strpos($articleId, $prefix) !== 0) {
        throw new RuntimeException('Approved Package article_id does not match editorial map prefix');
    }
    $suffix = substr($articleId, strlen($prefix));
    if ($suffix === '' || ctype_digit($suffix) === false) {
        throw new RuntimeException('Approved Package article_id has no numeric editorial-map suffix');
    }
    $number = (int) $suffix;
    $range = array_values($map['article_id_range']);
    if ($number < (int) $range[0] || $number > (int) $range[1]) {
        throw new RuntimeException('Approved Package article_id is outside editorial map range');
    }

    $mapPrimary = trim((string) $map['primary_seo_cluster_id']);
    $mapSecondary = array_values($map['secondary_seo_cluster_ids'] ?? []);
    $hasPackageCluster = array_key_exists('primary_seo_cluster_id', $package) || array_key_exists('secondary_seo_cluster_ids', $package);
    if ($hasPackageCluster) {
        $packagePrimary = trim((string) ($package['primary_seo_cluster_id'] ?? ''));
        $packageSecondary = array_values($package['secondary_seo_cluster_ids'] ?? []);
        if ($packagePrimary !== $mapPrimary || $packageSecondary !== $mapSecondary) {
            throw new RuntimeException('Approved Package SEO cluster metadata conflicts with explicit editorial map');
        }
    }

    $package['primary_seo_cluster_id'] = $mapPrimary;
    $package['secondary_seo_cluster_ids'] = $mapSecondary;
    return [$package, 'editorial_map:' . trim((string) $map['map_id'])];
}

function normalizeClusterMetadata(array $package, array $registry, string $siteCategoryKey): array
{
    $hasPrimary = array_key_exists('primary_seo_cluster_id', $package);
    $hasSecondary = array_key_exists('secondary_seo_cluster_ids', $package);
    if (!$hasPrimary && !$hasSecondary) {
        return [null, []];
    }
    $primary = trim((string) ($package['primary_seo_cluster_id'] ?? ''));
    $secondary = $package['secondary_seo_cluster_ids'] ?? [];
    if ($primary === '') {
        throw new RuntimeException('SEO cluster metadata requires a non-empty primary_seo_cluster_id');
    }
    if (!is_array($secondary)) {
        throw new RuntimeException('secondary_seo_cluster_ids must be an array');
    }
    if ($siteCategoryKey !== $registry['carrier_key']) {
        throw new RuntimeException('SEO cluster metadata is only valid for site_category_key=' . $registry['carrier_key']);
    }
    if (!isset($registry['ids'][$primary])) {
        throw new RuntimeException('unknown primary_seo_cluster_id: ' . $primary);
    }
    $normalizedSecondary = [];
    foreach ($secondary as $clusterId) {
        $clusterId = trim((string) $clusterId);
        if ($clusterId === '' || !isset($registry['ids'][$clusterId])) {
            throw new RuntimeException('unknown or empty secondary_seo_cluster_id: ' . $clusterId);
        }
        if ($clusterId === $primary) {
            throw new RuntimeException('primary SEO cluster must not repeat in secondary clusters');
        }
        if (in_array($clusterId, $normalizedSecondary, true)) {
            throw new RuntimeException('duplicate secondary SEO cluster id: ' . $clusterId);
        }
        $normalizedSecondary[] = $clusterId;
    }
    return [$primary, $normalizedSecondary];
}

function stableArticleKey(string $articleId): string
{
    $base = strtolower($articleId);
    $base = preg_replace('/[^a-z0-9_-]+/', '-', $base);
    $base = trim((string) $base, '-_');
    if ($base === '' || preg_match('/^[a-z0-9]/', $base) !== 1) {
        $base = 'lcm-' . substr(hash('sha256', $articleId), 0, 20);
    }
    if (strlen($base) > 64) {
        $base = substr($base, 0, 43) . '-' . substr(hash('sha256', $articleId), 0, 20);
    }
    if (strlen($base) < 3) {
        $base = 'lcm-' . $base . '-' . substr(hash('sha256', $articleId), 0, 8);
    }
    return $base;
}

function atomicWriteJson(string $target, array $payload): void
{
    $dir = dirname($target);
    if (!is_dir($dir) && !mkdir($dir, 0750, true) && !is_dir($dir)) {
        throw new RuntimeException('cannot create output directory: ' . $dir);
    }
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode draft JSON');
    }
    $tmp = $target . '.tmp.' . getmypid();
    if (file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary draft file');
    }
    if (!rename($tmp, $target)) {
        @unlink($tmp);
        throw new RuntimeException('cannot atomically replace draft file');
    }
}

function assertMetadataRefreshSafe(array $existing, array $draft): void
{
    if ((string) ($existing['publication_state'] ?? '') !== 'draft') {
        draftFail('metadata refresh requires existing publication_state=draft', 9);
    }
    if (array_key_exists('publish_at', $existing) && trim((string) ($existing['publish_at'] ?? '')) !== '') {
        draftFail('metadata refresh refuses a draft with publish_at', 10);
    }
    if ((string) ($existing['source_article_id'] ?? '') !== (string) $draft['source_article_id']) {
        draftFail('metadata refresh source_article_id mismatch', 11);
    }
    if ((string) ($existing['source_fingerprint'] ?? '') !== (string) $draft['source_fingerprint']) {
        draftFail('metadata refresh source_fingerprint mismatch', 12);
    }
    if (!hash_equals((string) ($existing['source_content_hash'] ?? ''), (string) $draft['source_content_hash'])) {
        draftFail('metadata refresh source_content_hash mismatch', 13);
    }
    if ((string) ($existing['content'] ?? '') !== (string) $draft['content']) {
        draftFail('metadata refresh content bytes differ; explicit revision workflow required', 14);
    }
    if ((string) ($existing['article_key'] ?? '') !== (string) $draft['article_key']) {
        draftFail('metadata refresh article_key mismatch', 15);
    }
}

$options = getopt('', ['input:', 'output::', 'category-map::', 'cluster-registry::', 'editorial-cluster-map::', 'refresh-metadata']);
$input = $options['input'] ?? ($argv[1] ?? '');
$refreshMetadata = array_key_exists('refresh-metadata', $options);
if ($input === '') {
    draftFail('Usage: php convert_approved_to_draft.php --input=approved.json [--output=draft.json] [--editorial-cluster-map=map.json] [--refresh-metadata]');
}
$repoRoot = dirname(__DIR__, 2);
$categoryMapPath = $options['category-map'] ?? ($repoRoot . '/config/content_category_map.json');
$clusterRegistryPath = $options['cluster-registry'] ?? ($repoRoot . '/content/seo_cluster_registry.json');
$editorialClusterMapPath = trim((string) ($options['editorial-cluster-map'] ?? ''));

try {
    $package = xyptdq_read_package_file($input);
    $validation = xyptdq_validate_approved_package($package);
    if (!$validation['passed']) {
        draftFail('Approved Package validation failed: ' . implode('; ', $validation['errors']), 2);
    }

    $contentFormat = strtolower(trim((string) ($package['content_format'] ?? '')));
    if ($contentFormat !== 'html') {
        draftFail('content_format must be explicit html before website conversion', 3);
    }

    $siteCategoryKey = trim((string) ($package['site_category_key'] ?? ''));
    if ($siteCategoryKey === '') {
        draftFail('site_category_key is required; category guessing is prohibited', 4);
    }
    $map = loadCategoryMap($categoryMapPath);
    $category = $map['categories'][$siteCategoryKey] ?? null;
    if (!is_array($category) || (int) ($category['catid'] ?? 0) <= 0) {
        draftFail('unknown or invalid site_category_key: ' . $siteCategoryKey, 5);
    }

    $clusterRegistry = loadClusterRegistry($clusterRegistryPath);
    $clusterAssignmentSource = null;
    if ($editorialClusterMapPath !== '') {
        $editorialMap = loadEditorialClusterMap($editorialClusterMapPath);
        [$package, $clusterAssignmentSource] = applyEditorialClusterMap($package, $editorialMap);
    }
    [$primaryCluster, $secondaryClusters] = normalizeClusterMetadata($package, $clusterRegistry, $siteCategoryKey);
    if ($primaryCluster !== null && $clusterAssignmentSource === null) {
        $clusterAssignmentSource = 'package';
    }

    $content = (string) $package['content'];
    if (mb_strlen(strip_tags($content), 'UTF-8') < 180) {
        draftFail('content is too thin for website draft (<180 visible characters)', 6);
    }

    $articleKey = stableArticleKey((string) $package['article_id']);
    $excerpt = trim((string) ($package['summary'] ?? $package['meta_description'] ?? ''));
    $draft = [
        'schema_version' => 1,
        'article_key' => $articleKey,
        'title' => trim((string) $package['title']),
        'slug' => trim((string) $package['slug']),
        'content' => $content,
        'excerpt' => $excerpt,
        'seo_title' => trim((string) ($package['seo_title'] ?? $package['title'])),
        'meta_description' => trim((string) $package['meta_description']),
        'primary_keyword' => trim((string) $package['primary_keyword']),
        'secondary_keywords' => array_values($package['secondary_keywords'] ?? []),
        'catid' => (int) $category['catid'],
        'site_category_key' => $siteCategoryKey,
        'thumbnail' => trim((string) ($package['thumbnail'] ?? '')),
        'internal_links' => array_values($package['internal_links'] ?? []),
        'author' => trim((string) ($package['author'] ?? '老彩迷编辑')),
        'content_type' => trim((string) ($package['content_type'] ?? 'guide')),
        'source_notes' => 'caipiaowenzhang approved article_id=' . (string) $package['article_id'],
        'commercial_disclosure' => (bool) ($package['commercial_disclosure'] ?? false),
        'publication_state' => 'draft',
        'source_article_id' => (string) $package['article_id'],
        'source_fingerprint' => (string) ($package['fingerprint'] ?? ''),
        'source_content_hash' => (string) ($package['content_hash'] ?? hash('sha256', $content)),
        'approved_at' => $package['approved_at'] ?? null,
        'converted_at' => gmdate('c'),
    ];
    if ($primaryCluster !== null) {
        $draft['primary_seo_cluster_id'] = $primaryCluster;
        $draft['secondary_seo_cluster_ids'] = $secondaryClusters;
        $draft['seo_cluster_assignment_source'] = $clusterAssignmentSource;
    }

    $defaultTarget = $repoRoot . '/content/drafts/' . $articleKey . '.json';
    $target = $options['output'] ?? $defaultTarget;
    if (is_file($target)) {
        $existing = json_decode((string) file_get_contents($target), true);
        if (!is_array($existing)) {
            draftFail('existing draft file is invalid JSON; refusing overwrite', 7);
        }
        $oldHash = (string) ($existing['source_content_hash'] ?? '');
        if ($oldHash === $draft['source_content_hash']) {
            if (!$refreshMetadata) {
                fwrite(STDOUT, json_encode([
                    'status' => 'unchanged',
                    'article_key' => $articleKey,
                    'catid' => $draft['catid'],
                    'output' => $target,
                    'warnings' => $validation['warnings'],
                ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
                exit(0);
            }
            assertMetadataRefreshSafe($existing, $draft);
            atomicWriteJson($target, $draft);
            fwrite(STDOUT, json_encode([
                'status' => 'draft_metadata_refreshed',
                'article_key' => $articleKey,
                'site_category_key' => $siteCategoryKey,
                'catid' => $draft['catid'],
                'output' => $target,
                'warnings' => $validation['warnings'],
            ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
            exit(0);
        }
        draftFail('draft exists with a different source_content_hash; explicit revision workflow required', 8);
    }

    atomicWriteJson($target, $draft);
    fwrite(STDOUT, json_encode([
        'status' => 'draft_created',
        'article_key' => $articleKey,
        'site_category_key' => $siteCategoryKey,
        'catid' => $draft['catid'],
        'output' => $target,
        'warnings' => $validation['warnings'],
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
} catch (Throwable $e) {
    draftFail($e->getMessage(), 1);
}

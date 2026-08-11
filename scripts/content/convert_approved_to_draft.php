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

$options = getopt('', ['input:', 'output::', 'category-map::']);
$input = $options['input'] ?? ($argv[1] ?? '');
if ($input === '') {
    draftFail('Usage: php convert_approved_to_draft.php --input=approved.json [--output=draft.json]');
}
$repoRoot = dirname(__DIR__, 2);
$categoryMapPath = $options['category-map'] ?? ($repoRoot . '/config/content_category_map.json');

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

    $defaultTarget = $repoRoot . '/content/drafts/' . $articleKey . '.json';
    $target = $options['output'] ?? $defaultTarget;
    if (is_file($target)) {
        $existing = json_decode((string) file_get_contents($target), true);
        if (!is_array($existing)) {
            draftFail('existing draft file is invalid JSON; refusing overwrite', 7);
        }
        $oldHash = (string) ($existing['source_content_hash'] ?? '');
        if ($oldHash === $draft['source_content_hash']) {
            fwrite(STDOUT, json_encode([
                'status' => 'unchanged',
                'article_key' => $articleKey,
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

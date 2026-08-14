#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/public_release_package.php';

function canaryTestFail(string $message): void
{
    fwrite(STDERR, '[public-release-canary-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function canaryTestWrite(string $path, array $payload): void
{
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($path, $json . PHP_EOL) === false) {
        canaryTestFail('cannot write fixture: ' . $path);
    }
}

$repoRoot = dirname(__DIR__, 2);
$ingest = __DIR__ . '/ingest_public_release_canary.php';
$tmp = sys_get_temp_dir() . '/xyptdq-public-release-canary-' . getmypid();
if (!mkdir($tmp, 0750, true) && !is_dir($tmp)) {
    canaryTestFail('cannot create temp directory');
}

try {
    $parentContent = '<p>General educational parent document for canary contract testing.</p>' . str_repeat('<p>Reference paragraph for visible length.</p>', 12);
    $parent = [
        'article_id' => 'LCM-CANARY-001',
        'title' => 'Generic canary document for website intake',
        'slug' => 'generic-canary-document',
        'meta_description' => 'Generic metadata for a website public-release canary intake test.',
        'primary_keyword' => 'generic canary document',
        'secondary_keywords' => ['generic documentation'],
        'search_intent' => 'documentation test',
        'content' => $parentContent,
        'content_format' => 'html',
        'content_hash' => hash('sha256', $parentContent),
        'fingerprint' => 'immutable-parent-fingerprint',
        'category' => 'documentation',
        'rule_refs' => [],
        'source_refs' => [],
        'status' => 'approved',
        'content_type' => 'technique_article',
        'site_category_key' => 'tzjq',
        'creator_batch_id' => 'TEST-CANARY-BATCH',
        'summary' => 'Generic canary summary.',
    ];

    $revision = $parent;
    $revision['content'] .= '<p>Separately reviewed website-facing revision.</p>';
    $revision['content_hash'] = hash('sha256', $revision['content']);
    $revision['revision_kind'] = 'website_public_release';
    $revision['release_revision'] = 1;
    $revision['revision_id'] = 'LCM-CANARY-001:public-r1';
    $revision['parent_content_hash'] = $parent['content_hash'];
    $revision['parent_fingerprint'] = $parent['fingerprint'];
    $revision['source_batch_id'] = $parent['creator_batch_id'];
    $revision['public_release_review'] = [
        'status' => 'approved',
        'reviewed_at' => '2026-08-14T00:00:00Z',
        'review_contract' => 'website-public-release-v1',
    ];
    $revision['fingerprint'] = xyptdq_public_release_expected_fingerprint($revision);

    $manifest = [
        'schema_version' => 1,
        'source_batch_id' => 'TEST-CANARY-BATCH',
        'revision_kind' => 'website_public_release',
        'expected_count' => 50,
        'approved_public_release_count' => 1,
        'status' => 'partial',
        'website_batch_ingestion_allowed' => false,
        'canary_ingestion_allowed' => true,
        'articles' => [[
            'article_id' => $revision['article_id'],
            'revision_id' => $revision['revision_id'],
            'release_revision' => 1,
            'slug' => $revision['slug'],
            'primary_keyword' => $revision['primary_keyword'],
            'content_hash' => $revision['content_hash'],
            'fingerprint' => $revision['fingerprint'],
            'path' => 'articles/public_release/TEST-CANARY-BATCH/LCM-CANARY-001.public-r1.json',
        ]],
    ];

    $editorialMap = [
        'schema_version' => 1,
        'map_id' => 'TEST-CANARY-ffc-research',
        'batch_id' => 'TEST-CANARY-BATCH',
        'article_id_prefix' => 'LCM-CANARY-',
        'article_id_range' => [1, 1],
        'primary_seo_cluster_id' => 'ffc_research',
        'secondary_seo_cluster_ids' => [],
        'assignment_type' => 'editorial_batch_contract',
    ];

    $parentPath = $tmp . '/parent.json';
    $revisionPath = $tmp . '/revision.json';
    $manifestPath = $tmp . '/manifest.json';
    $mapPath = $tmp . '/map.json';
    $draftPath = $tmp . '/draft.json';
    canaryTestWrite($parentPath, $parent);
    canaryTestWrite($revisionPath, $revision);
    canaryTestWrite($manifestPath, $manifest);
    canaryTestWrite($mapPath, $editorialMap);

    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($ingest)
        . ' --revision=' . escapeshellarg($revisionPath)
        . ' --parent=' . escapeshellarg($parentPath)
        . ' --manifest=' . escapeshellarg($manifestPath)
        . ' --editorial-cluster-map=' . escapeshellarg($mapPath)
        . ' --output=' . escapeshellarg($draftPath);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code !== 0) {
        canaryTestFail('valid canary intake failed: ' . implode("\n", $out));
    }

    $draft = json_decode((string) file_get_contents($draftPath), true);
    if (!is_array($draft)) {
        canaryTestFail('generated Draft is invalid');
    }
    if (($draft['publication_state'] ?? null) !== 'draft' || array_key_exists('publish_at', $draft)) {
        canaryTestFail('generated canary is not Draft-only');
    }
    if (($draft['primary_seo_cluster_id'] ?? null) !== 'ffc_research') {
        canaryTestFail('editorial Cluster was not applied');
    }
    if (($draft['seo_cluster_assignment_source'] ?? null) !== 'editorial_map:TEST-CANARY-ffc-research') {
        canaryTestFail('Cluster assignment source missing');
    }
    foreach ([
        'source_revision_kind' => 'website_public_release',
        'source_revision_id' => 'LCM-CANARY-001:public-r1',
        'source_batch_id' => 'TEST-CANARY-BATCH',
        'source_creator_batch_id' => 'TEST-CANARY-BATCH',
        'source_parent_content_hash' => $parent['content_hash'],
        'source_parent_fingerprint' => $parent['fingerprint'],
        'source_intake_mode' => 'public_release_canary',
    ] as $field => $expected) {
        if (($draft[$field] ?? null) !== $expected) {
            canaryTestFail('Draft provenance mismatch: ' . $field);
        }
    }
    if (($draft['source_content_hash'] ?? null) !== $revision['content_hash']) {
        canaryTestFail('Draft does not preserve revision content hash');
    }

    $badManifest = $manifest;
    $badManifest['canary_ingestion_allowed'] = false;
    $badManifestPath = $tmp . '/bad-manifest.json';
    $badDraftPath = $tmp . '/bad-draft.json';
    canaryTestWrite($badManifestPath, $badManifest);
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($ingest)
        . ' --revision=' . escapeshellarg($revisionPath)
        . ' --parent=' . escapeshellarg($parentPath)
        . ' --manifest=' . escapeshellarg($badManifestPath)
        . ' --editorial-cluster-map=' . escapeshellarg($mapPath)
        . ' --output=' . escapeshellarg($badDraftPath);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code === 0 || is_file($badDraftPath)) {
        canaryTestFail('manifest gate failed open');
    }

    fwrite(STDOUT, "[public-release-canary-test] PASS validation=required cluster=applied provenance=preserved lifecycle=draft_only\n");
} finally {
    foreach (glob($tmp . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmp);
}

#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/public_release_package.php';

function testFail(string $message): void
{
    fwrite(STDERR, '[public-release-intake-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function baseParent(): array
{
    $content = '<p>General educational source document for website intake contract testing.</p>' . str_repeat('<p>Reference material.</p>', 12);
    return [
        'article_id' => 'TEST-PUBLIC-001',
        'title' => 'Generic public release test article',
        'slug' => 'generic-public-release-test',
        'meta_description' => 'Generic metadata used for a public-release intake contract test.',
        'primary_keyword' => 'generic public release test',
        'secondary_keywords' => [],
        'search_intent' => 'documentation test',
        'content' => $content,
        'content_format' => 'html',
        'content_hash' => hash('sha256', $content),
        'fingerprint' => 'parent-fingerprint-001',
        'category' => 'documentation',
        'rule_refs' => [],
        'source_refs' => [],
        'status' => 'approved',
        'content_type' => 'technique_article',
        'site_category_key' => 'tzjq',
        'creator_batch_id' => 'TEST-BATCH-001',
    ];
}

function makeRevision(array $parent): array
{
    $revision = $parent;
    $revision['content'] = $parent['content'] . '<p>Reviewed website-facing revision.</p>';
    $revision['content_hash'] = hash('sha256', $revision['content']);
    $revision['revision_kind'] = 'website_public_release';
    $revision['release_revision'] = 1;
    $revision['revision_id'] = $parent['article_id'] . ':public-r1';
    $revision['parent_content_hash'] = $parent['content_hash'];
    $revision['parent_fingerprint'] = $parent['fingerprint'];
    $revision['source_batch_id'] = $parent['creator_batch_id'];
    $revision['public_release_review'] = [
        'status' => 'approved',
        'reviewed_at' => '2026-08-14T00:00:00Z',
        'review_contract' => 'website-public-release-v1',
    ];
    $revision['fingerprint'] = xyptdq_public_release_expected_fingerprint($revision);
    return $revision;
}

function makeManifest(array $revision): array
{
    return [
        'schema_version' => 1,
        'source_batch_id' => $revision['source_batch_id'],
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
            'path' => 'articles/public_release/TEST-BATCH-001/TEST-PUBLIC-001.public-r1.json',
        ]],
    ];
}

$parent = baseParent();
$revision = makeRevision($parent);
$manifest = makeManifest($revision);

$valid = xyptdq_validate_public_release_intake($revision, $parent, $manifest, 'canary');
if (!$valid['passed']) {
    testFail('valid canary rejected: ' . implode('; ', $valid['errors']));
}

$badParentLink = $revision;
$badParentLink['parent_content_hash'] = str_repeat('0', 64);
$badParentLink['fingerprint'] = xyptdq_public_release_expected_fingerprint($badParentLink);
$result = xyptdq_validate_public_release_intake($badParentLink, $parent, $manifest, 'canary');
if ($result['passed'] || !in_array('parent_content_hash does not match immutable parent', $result['errors'], true)) {
    testFail('parent hash mismatch was not rejected');
}

$badManifest = $manifest;
$badManifest['articles'][0]['content_hash'] = str_repeat('f', 64);
$result = xyptdq_validate_public_release_intake($revision, $parent, $badManifest, 'canary');
if ($result['passed'] || !in_array('manifest does not contain the exact revision identity', $result['errors'], true)) {
    testFail('manifest revision mismatch was not rejected');
}

$result = xyptdq_validate_public_release_intake($revision, $parent, $manifest, 'batch');
if ($result['passed']) {
    testFail('partial manifest incorrectly passed full-batch mode');
}

$missingCreator = $revision;
unset($missingCreator['creator_batch_id']);
$missingCreator['fingerprint'] = xyptdq_public_release_expected_fingerprint($missingCreator);
$result = xyptdq_validate_public_release_intake($missingCreator, $parent, $manifest, 'canary');
if ($result['passed']) {
    testFail('missing creator_batch_id was not rejected');
}

fwrite(STDOUT, "[public-release-intake-test] PASS valid_canary=accepted parent_link=guarded manifest=guarded batch_gate=guarded creator_batch=guarded\n");

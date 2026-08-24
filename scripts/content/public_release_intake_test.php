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

function titleSeoGates(bool $allPass = true): array
{
    $names = [
        'TITLE_TOPIC_MATCH',
        'TITLE_DUPLICATION_CHECK',
        'TITLE_KEYWORD_DIVERSITY',
        'TITLE_NUMERIC_CLAIM_VERIFIED',
        'TITLE_SEARCH_INTENT_CHECK',
        'TITLE_CLICKABILITY_CHECK',
    ];
    $gates = [];
    foreach ($names as $name) {
        $gates[$name] = ['passed' => true, 'reasons' => [], 'details' => []];
    }
    if (!$allPass) {
        $gates['TITLE_DUPLICATION_CHECK'] = [
            'passed' => false,
            'reasons' => ['synthetic duplicate test'],
            'details' => ['score' => 0.91],
        ];
    }
    return $gates;
}

function applyTitleSeo(array $revision, string $title, bool $allPass = true): array
{
    $candidates = [
        $title,
        '先看输入还是先看输出？通用测试文章的检查顺序',
        '从规则到复核：通用测试文章最容易忽略什么',
    ];
    $revision['title'] = $title;
    $revision['seo_title'] = $title;
    $revision['title_seo_contract_version'] = '1.0';
    $revision['title_candidates'] = $candidates;
    $revision['title_selection_reason'] = 'test-selected title from reviewed candidate set';
    $revision['title_review'] = [
        'passed' => $allPass,
        'contract_version' => '1.0',
        'selected_title' => $title,
        'candidates' => $candidates,
        'gates' => titleSeoGates($allPass),
    ];
    $revision['fingerprint'] = xyptdq_public_release_expected_fingerprint($revision);
    return $revision;
}

$parent = baseParent();
$revision = makeRevision($parent);
$manifest = makeManifest($revision);

$valid = xyptdq_validate_public_release_intake($revision, $parent, $manifest, 'canary');
if (!$valid['passed']) {
    testFail('valid legacy canary rejected: ' . implode('; ', $valid['errors']));
}
if (($valid['title_seo']['applicable'] ?? null) !== false) {
    testFail('legacy package unexpectedly required Title SEO metadata');
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

$titleRevision = applyTitleSeo(makeRevision($parent), '候选空间为什么会变？通用测试文章的复核边界');
$titleManifest = makeManifest($titleRevision);
$result = xyptdq_validate_public_release_intake($titleRevision, $parent, $titleManifest, 'canary');
if (!$result['passed'] || ($result['title_seo']['required_gates_verified'] ?? 0) !== 6) {
    testFail('valid Title SEO V1.0 revision rejected: ' . implode('; ', $result['errors']));
}

$failedGate = applyTitleSeo(makeRevision($parent), '从输入到输出：通用测试文章怎样复核', false);
$failedGateManifest = makeManifest($failedGate);
$result = xyptdq_validate_public_release_intake($failedGate, $parent, $failedGateManifest, 'canary');
if ($result['passed']) {
    testFail('failed Title SEO gate was not rejected');
}
$failedGateFound = false;
foreach ($result['errors'] as $error) {
    if (strpos($error, 'TITLE_DUPLICATION_CHECK') !== false) {
        $failedGateFound = true;
        break;
    }
}
if (!$failedGateFound) {
    testFail('failed Title SEO gate reason was not surfaced');
}

$reservedParent = baseParent();
$reservedParent['article_id'] = 'TEST-PUBLIC-RESERVED';
$reservedParent['slug'] = 'generic-reserved-keyword-test';
$reservedParent['primary_keyword'] = '分分彩技巧';
$reservedParent['fingerprint'] = 'parent-fingerprint-reserved';
$reservedRevision = applyTitleSeo(makeRevision($reservedParent), '从规则到复核：这套技巧最容易忽略什么');
$reservedManifest = makeManifest($reservedRevision);
$result = xyptdq_validate_public_release_intake($reservedRevision, $reservedParent, $reservedManifest, 'canary');
if ($result['passed']) {
    testFail('reserved broad primary_keyword was not rejected');
}
$reservedFound = false;
foreach ($result['errors'] as $error) {
    if (strpos($error, 'primary_keyword conflicts with reserved site target') !== false) {
        $reservedFound = true;
        break;
    }
}
if (!$reservedFound) {
    testFail('reserved primary_keyword conflict reason was not surfaced');
}

$claimRevision = applyTitleSeo(makeRevision($parent), '分分彩稳赚方案的完整操作步骤');
$claimManifest = makeManifest($claimRevision);
$result = xyptdq_validate_public_release_intake($claimRevision, $parent, $claimManifest, 'canary');
if ($result['passed']) {
    testFail('unqualified prohibited title claim was not rejected');
}

$criticalRevision = applyTitleSeo(makeRevision($parent), '分分彩稳赚真的可信吗？先看规则和风险边界');
$criticalManifest = makeManifest($criticalRevision);
$result = xyptdq_validate_public_release_intake($criticalRevision, $parent, $criticalManifest, 'canary');
if (!$result['passed']) {
    testFail('critical/question framing of a prohibited claim was incorrectly rejected: ' . implode('; ', $result['errors']));
}

fwrite(STDOUT, "[public-release-intake-test] PASS legacy=accepted parent_link=guarded manifest=guarded batch_gate=guarded creator_batch=guarded title_seo=guarded reserved_keyword=guarded sensitive_claim=guarded\n");

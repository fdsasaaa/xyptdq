#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/approved_package.php';

function check(bool $condition, string $message): void
{
    if (!$condition) {
        fwrite(STDERR, '[content-self-test] FAIL: ' . $message . PHP_EOL);
        exit(1);
    }
}

function runCommand(string $command): array
{
    $output = [];
    $code = 0;
    exec($command . ' 2>&1', $output, $code);
    return [$code, implode("\n", $output)];
}

$content = str_repeat('<p>这是用于验证草稿接收桥梁的测试正文，不代表真实文章。</p>', 20);
$good = [
    'article_id' => 'LCM-TEST-001',
    'title' => '测试文章：Approved Package 草稿桥梁验证',
    'slug' => 'test-article',
    'meta_description' => '用于桥梁离线自测的描述。',
    'primary_keyword' => '测试关键词',
    'secondary_keywords' => ['测试'],
    'search_intent' => '测试接收桥梁',
    'category' => '测试',
    'site_category_key' => 'tzjq',
    'tags' => ['测试'],
    'content' => $content,
    'content_format' => 'html',
    'summary' => '用于验证Approved Package安全转换成网站草稿。',
    'internal_links' => [],
    'rule_refs' => ['R-TEST'],
    'source_refs' => ['S-TEST'],
    'case_scope' => 'mechanics_only',
    'fingerprint' => 'FP-TEST',
    'content_hash' => hash('sha256', $content),
    'status' => 'approved',
];

$result = xyptdq_validate_approved_package($good);
check($result['passed'] === true, 'valid approved package must pass');

$badStatus = $good;
$badStatus['status'] = 'draft';
check(xyptdq_validate_approved_package($badStatus)['passed'] === false, 'draft status must fail');

$badHash = $good;
$badHash['content_hash'] = str_repeat('0', 64);
check(xyptdq_validate_approved_package($badHash)['passed'] === false, 'tampered content hash must fail');

$tmp = sys_get_temp_dir() . '/xyptdq-content-self-test-' . getmypid();
$queue = $tmp . '/queue';
@mkdir($tmp, 0750, true);
$input = $tmp . '/approved.json';
file_put_contents($input, json_encode($good, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));

// v0.1 ingress staging remains idempotent.
$stageScript = __DIR__ . '/stage_approved_package.php';
$stageCmd = 'XYPTDQ_CONTENT_QUEUE=' . escapeshellarg($queue) . ' '
    . escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($stageScript) . ' ' . escapeshellarg($input);
[$code1, $output1] = runCommand($stageCmd);
check($code1 === 0, 'first staging must succeed: ' . $output1);
[$code2, $output2] = runCommand($stageCmd);
check($code2 === 0, 'idempotent restaging must succeed: ' . $output2);
$pending = glob($queue . '/pending/*.json') ?: [];
check(count($pending) === 1, 'same article/hash must create exactly one pending file');

// v0.2 conversion must fail closed when category intent is missing.
$convertScript = __DIR__ . '/convert_approved_to_draft.php';
$missingCategory = $good;
unset($missingCategory['site_category_key']);
$missingInput = $tmp . '/missing-category.json';
file_put_contents($missingInput, json_encode($missingCategory, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
$badDraft = $tmp . '/bad-draft.json';
[$badCode, ] = runCommand(
    escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($convertScript)
    . ' --input=' . escapeshellarg($missingInput)
    . ' --output=' . escapeshellarg($badDraft)
);
check($badCode !== 0, 'conversion without site_category_key must fail');
check(!is_file($badDraft), 'failed conversion must not produce a draft');

// Approved Package -> isolated draft. tzjq is canonical catid 3.
$draftPath = $tmp . '/lcm-test-001.json';
[$convertCode, $convertOutput] = runCommand(
    escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($convertScript)
    . ' --input=' . escapeshellarg($input)
    . ' --output=' . escapeshellarg($draftPath)
);
check($convertCode === 0, 'Approved Package conversion must succeed: ' . $convertOutput);
check(is_file($draftPath), 'draft file must exist');
$draft = json_decode((string) file_get_contents($draftPath), true);
check(is_array($draft), 'draft must be valid JSON');
check(($draft['publication_state'] ?? '') === 'draft', 'conversion must create draft state only');
check((int) ($draft['catid'] ?? 0) === 3, 'tzjq must map to canonical catid 3');
check(($draft['article_key'] ?? '') === 'lcm-test-001', 'article_key must be deterministic from article_id');
check(!array_key_exists('publish_at', $draft), 'draft must not have publish_at');

// Draft -> scheduled requires explicit promotion with a concrete publish time.
$promoteScript = __DIR__ . '/promote_draft.php';
$scheduledPath = $tmp . '/scheduled-lcm-test-001.json';
$publishAt = '2026-08-12T09:00:00+08:00';
[$promoteCode, $promoteOutput] = runCommand(
    escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($promoteScript)
    . ' --input=' . escapeshellarg($draftPath)
    . ' --publish-at=' . escapeshellarg($publishAt)
    . ' --output=' . escapeshellarg($scheduledPath)
);
check($promoteCode === 0, 'explicit draft promotion must succeed: ' . $promoteOutput);
$scheduled = json_decode((string) file_get_contents($scheduledPath), true);
check(is_array($scheduled), 'scheduled file must be valid JSON');
check(($scheduled['publication_state'] ?? '') === 'scheduled', 'promote must set scheduled state');
check(($scheduled['publish_at'] ?? '') === $publishAt, 'promote must preserve explicit publish time');
check(($scheduled['source_content_hash'] ?? '') === ($draft['source_content_hash'] ?? ''), 'promotion must preserve source content hash');

foreach (glob($tmp . '/queue/pending/*') ?: [] as $file) {
    @unlink($file);
}
@rmdir($queue . '/pending');
@rmdir($queue);
foreach ([$input, $missingInput, $draftPath, $scheduledPath] as $file) {
    @unlink($file);
}
@rmdir($tmp);

fwrite(STDOUT, "[content-self-test] PASS\n");

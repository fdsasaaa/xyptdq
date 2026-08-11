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

$content = str_repeat('这是用于验证草稿接收桥梁的测试正文，不代表真实文章。', 20);
$good = [
    'article_id' => 'LCM-TEST-001',
    'title' => '测试文章',
    'slug' => 'test-article',
    'meta_description' => '用于桥梁离线自测的描述。',
    'primary_keyword' => '测试关键词',
    'secondary_keywords' => ['测试'],
    'search_intent' => '测试接收桥梁',
    'category' => '测试',
    'tags' => ['测试'],
    'content' => $content,
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

$script = __DIR__ . '/stage_approved_package.php';
$cmd = 'XYPTDQ_CONTENT_QUEUE=' . escapeshellarg($queue) . ' '
    . escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($script) . ' ' . escapeshellarg($input);
$output1 = [];
$code1 = 0;
exec($cmd . ' 2>&1', $output1, $code1);
check($code1 === 0, 'first staging must succeed: ' . implode("\n", $output1));

$output2 = [];
$code2 = 0;
exec($cmd . ' 2>&1', $output2, $code2);
check($code2 === 0, 'idempotent restaging must succeed');
$pending = glob($queue . '/pending/*.json') ?: [];
check(count($pending) === 1, 'same article/hash must create exactly one pending file');

foreach (glob($tmp . '/queue/pending/*') ?: [] as $file) {
    @unlink($file);
}
@rmdir($queue . '/pending');
@rmdir($queue);
@unlink($input);
@rmdir($tmp);

fwrite(STDOUT, "[content-self-test] PASS\n");

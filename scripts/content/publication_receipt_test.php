#!/usr/bin/env php
<?php
declare(strict_types=1);

$exporter = __DIR__ . '/export_publication_receipt.php';
$tmp = sys_get_temp_dir() . '/xyptdq-publication-receipt-' . getmypid();

function receiptTestFail(string $message): void
{
    fwrite(STDERR, '[publication-receipt-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function receiptTestWrite(string $path, array $data): void
{
    $json = json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($path, $json . PHP_EOL) === false) {
        receiptTestFail('cannot write fixture: ' . $path);
    }
}

function receiptTestRun(string $exporter, string $article, string $state, string $output = ''): array
{
    $lines = [];
    $code = 0;
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($exporter)
        . ' --article=' . escapeshellarg($article)
        . ' --state=' . escapeshellarg($state);
    if ($output !== '') {
        $cmd .= ' --output=' . escapeshellarg($output);
    }
    exec($cmd . ' 2>&1', $lines, $code);
    return ['code' => $code, 'output' => implode("\n", $lines)];
}

function receiptFixtureArticle(): array
{
    $content = str_repeat('<p>可验证的未来发布回执测试正文。</p>', 20);
    return [
        'schema_version' => 1,
        'article_key' => 'lcm-idea-test-receipt',
        'title' => '分分彩定位胆冷热技巧：发布回执测试文章',
        'slug' => 'receipt-test',
        'content' => $content,
        'primary_keyword' => '分分彩定位胆冷热技巧',
        'catid' => 3,
        'site_category_key' => 'tzjq',
        'publication_state' => 'scheduled',
        'publish_at' => '2026-08-12T09:00:00+08:00',
        'source_article_id' => 'LCM-IDEA-TEST-RECEIPT',
        'source_fingerprint' => str_repeat('a', 64),
        'source_content_hash' => hash('sha256', $content),
    ];
}

function receiptPublisherHash(array $article): string
{
    $json = json_encode($article, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        receiptTestFail('cannot encode fixture article hash');
    }
    return hash('sha256', $json);
}

if (!mkdir($tmp, 0750, true) && !is_dir($tmp)) {
    receiptTestFail('cannot create temp directory');
}
$articlePath = $tmp . '/article.json';
$statePath = $tmp . '/state.json';
$outputPath = $tmp . '/receipt.json';

try {
    $article = receiptFixtureArticle();
    receiptTestWrite($articlePath, $article);
    $state = [
        'version' => 1,
        'articles' => [
            $article['article_key'] => [
                'status' => 'published',
                'content_hash' => receiptPublisherHash($article),
                'cms_id' => 321,
                'published_at' => '2026-08-11T14:30:00+00:00',
                'retry_count' => 0,
                'last_error' => null,
            ],
        ],
    ];
    receiptTestWrite($statePath, $state);

    $run = receiptTestRun($exporter, $articlePath, $statePath, $outputPath);
    if ($run['code'] !== 0 || strpos($run['output'], 'receipt_created') === false) {
        receiptTestFail('valid published state did not create receipt: ' . $run['output']);
    }
    $receipt = json_decode((string) file_get_contents($outputPath), true);
    if (!is_array($receipt)) {
        receiptTestFail('created receipt is invalid JSON');
    }
    if (($receipt['article_id'] ?? '') !== 'LCM-IDEA-TEST-RECEIPT') {
        receiptTestFail('article_id was not preserved');
    }
    if ((int) ($receipt['cms_id'] ?? 0) !== 321) {
        receiptTestFail('cms_id was not preserved');
    }
    if (($receipt['published_url'] ?? '') !== 'https://www.laocaimi.org/index.php?c=show&id=321') {
        receiptTestFail('published URL did not use native CMS route');
    }
    if (($receipt['content_hash'] ?? '') !== $article['source_content_hash']) {
        receiptTestFail('source content hash did not survive receipt export');
    }
    if (!preg_match('/^[a-f0-9]{64}$/', (string) ($receipt['receipt_id'] ?? ''))) {
        receiptTestFail('receipt_id missing or invalid');
    }

    // Idempotent re-export must not rewrite a different receipt.
    $run = receiptTestRun($exporter, $articlePath, $statePath, $outputPath);
    if ($run['code'] !== 0 || strpos($run['output'], 'unchanged') === false) {
        receiptTestFail('idempotent receipt export was not unchanged');
    }

    // Runtime state must prove publication, not merely contain a CMS id.
    $notPublished = $state;
    $notPublished['articles'][$article['article_key']]['status'] = 'scheduled';
    receiptTestWrite($statePath, $notPublished);
    $run = receiptTestRun($exporter, $articlePath, $statePath);
    if ($run['code'] === 0 || strpos($run['output'], 'state is not published') === false) {
        receiptTestFail('non-published state was not rejected');
    }

    // Runtime publisher hash must match the exact scheduled JSON object.
    $badState = $state;
    $badState['articles'][$article['article_key']]['content_hash'] = str_repeat('0', 64);
    receiptTestWrite($statePath, $badState);
    $run = receiptTestRun($exporter, $articlePath, $statePath);
    if ($run['code'] === 0 || strpos($run['output'], 'content_hash does not match scheduled article bytes') === false) {
        receiptTestFail('publisher state hash mismatch was not rejected');
    }

    // Approved-package body hash must still match the scheduled content bytes.
    $badArticle = $article;
    $badArticle['source_content_hash'] = str_repeat('0', 64);
    receiptTestWrite($articlePath, $badArticle);
    receiptTestWrite($statePath, $state);
    $run = receiptTestRun($exporter, $articlePath, $statePath);
    if ($run['code'] === 0 || strpos($run['output'], 'source_content_hash mismatch') === false) {
        receiptTestFail('source body hash mismatch was not rejected');
    }

    // Pre-bridge scheduled content cannot manufacture a modern publication receipt.
    $legacy = [
        'schema_version' => 1,
        'article_key' => 'seo-legacy',
        'title' => '历史内容不具备新桥梁身份字段',
        'content' => str_repeat('<p>legacy</p>', 20),
        'primary_keyword' => '分分彩技巧',
        'catid' => 3,
        'publish_at' => '2026-08-12T09:00:00+08:00',
    ];
    receiptTestWrite($articlePath, $legacy);
    $legacyState = [
        'articles' => [
            'seo-legacy' => [
                'status' => 'published',
                'content_hash' => receiptPublisherHash($legacy),
                'cms_id' => 99,
                'published_at' => '2026-08-11T14:30:00+00:00',
            ],
        ],
    ];
    receiptTestWrite($statePath, $legacyState);
    $run = receiptTestRun($exporter, $articlePath, $statePath);
    if ($run['code'] === 0 || strpos($run['output'], 'publication_state=scheduled') === false) {
        receiptTestFail('legacy pre-bridge file unexpectedly produced a receipt');
    }
} finally {
    foreach (glob($tmp . '/*') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmp);
}

fwrite(STDOUT, "[publication-receipt-test] PASS published-proof=1 url=verified idempotent=1 scheduled-state=blocked publisher-hash=blocked body-hash=blocked legacy=blocked\n");

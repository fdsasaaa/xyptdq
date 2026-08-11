#!/usr/bin/env php
<?php
declare(strict_types=1);

function receiptFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[publication-receipt] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function receiptLoadJson(string $path, string $label): array
{
    if (!is_file($path)) {
        throw new RuntimeException($label . ' not found: ' . $path);
    }
    $raw = file_get_contents($path);
    $data = $raw === false ? null : json_decode($raw, true);
    if (!is_array($data) || json_last_error() !== JSON_ERROR_NONE) {
        throw new RuntimeException('invalid ' . $label . ' JSON: ' . $path);
    }
    return $data;
}

function receiptPublisherArticleHash(array $article): string
{
    $json = json_encode($article, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode scheduled article for publisher hash');
    }
    return hash('sha256', $json);
}

function receiptId(array $receipt): string
{
    $parts = [
        'v1',
        (string) $receipt['article_id'],
        (string) $receipt['article_key'],
        (string) $receipt['fingerprint'],
        (string) $receipt['content_hash'],
        (string) $receipt['cms_id'],
        (string) $receipt['published_url'],
        (string) $receipt['published_at'],
        (string) $receipt['publisher_article_hash'],
        (string) $receipt['source_file'],
    ];
    return hash('sha256', implode('|', $parts));
}

function receiptAtomicWrite(string $path, array $payload): void
{
    $dir = dirname($path);
    if (!is_dir($dir) && !mkdir($dir, 0750, true) && !is_dir($dir)) {
        throw new RuntimeException('cannot create output directory: ' . $dir);
    }
    $json = json_encode($payload, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode publication receipt');
    }
    $tmp = $path . '.tmp.' . getmypid();
    if (file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary receipt: ' . $tmp);
    }
    if (!rename($tmp, $path)) {
        @unlink($tmp);
        throw new RuntimeException('cannot atomically replace receipt: ' . $path);
    }
}

$options = getopt('', ['article:', 'state:', 'output::', 'base-url::']);
$articlePath = $options['article'] ?? '';
$statePath = $options['state'] ?? '';
$outputPath = $options['output'] ?? '';
$baseUrl = rtrim((string) ($options['base-url'] ?? 'https://www.laocaimi.org'), '/');

if ($articlePath === '' || $statePath === '') {
    receiptFail('Usage: php export_publication_receipt.php --article=scheduled.json --state=publisher-state.json [--output=receipt.json]');
}

try {
    $base = parse_url($baseUrl);
    $baseHost = strtolower((string) ($base['host'] ?? ''));
    if (($base['scheme'] ?? '') !== 'https' || !in_array($baseHost, ['laocaimi.org', 'www.laocaimi.org'], true)) {
        throw new RuntimeException('base-url must be HTTPS laocaimi.org');
    }
    if (!empty($base['query']) || !empty($base['fragment']) || !empty($base['user']) || !empty($base['pass'])) {
        throw new RuntimeException('base-url must not contain query, fragment, or credentials');
    }

    $article = receiptLoadJson($articlePath, 'scheduled article');
    if ((string) ($article['publication_state'] ?? '') !== 'scheduled') {
        throw new RuntimeException('receipt export requires publication_state=scheduled');
    }
    $articleKey = trim((string) ($article['article_key'] ?? ''));
    $articleId = trim((string) ($article['source_article_id'] ?? ''));
    $fingerprint = strtolower(trim((string) ($article['source_fingerprint'] ?? '')));
    $contentHash = strtolower(trim((string) ($article['source_content_hash'] ?? '')));
    $content = (string) ($article['content'] ?? '');
    if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', $articleKey)) {
        throw new RuntimeException('invalid article_key');
    }
    if ($articleId === '') {
        throw new RuntimeException('managed scheduled article missing source_article_id');
    }
    if (!preg_match('/^[a-f0-9]{64}$/', $fingerprint)) {
        throw new RuntimeException('managed scheduled article has invalid source_fingerprint');
    }
    if (!preg_match('/^[a-f0-9]{64}$/', $contentHash) || !hash_equals($contentHash, hash('sha256', $content))) {
        throw new RuntimeException('managed scheduled article source_content_hash mismatch');
    }
    if (trim((string) ($article['publish_at'] ?? '')) === '') {
        throw new RuntimeException('managed scheduled article missing publish_at');
    }

    $state = receiptLoadJson($statePath, 'publisher state');
    if (!isset($state['articles']) || !is_array($state['articles'])) {
        throw new RuntimeException('publisher state missing articles map');
    }
    $entry = $state['articles'][$articleKey] ?? null;
    if (!is_array($entry)) {
        throw new RuntimeException('publisher state has no entry for article_key: ' . $articleKey);
    }
    if ((string) ($entry['status'] ?? '') !== 'published') {
        throw new RuntimeException('publisher state is not published for article_key: ' . $articleKey);
    }
    $cmsId = (int) ($entry['cms_id'] ?? 0);
    if ($cmsId <= 0) {
        throw new RuntimeException('published state has invalid cms_id');
    }
    $publishedAtRaw = trim((string) ($entry['published_at'] ?? ''));
    if ($publishedAtRaw === '') {
        throw new RuntimeException('published state missing published_at');
    }
    try {
        $publishedAt = new DateTimeImmutable($publishedAtRaw);
    } catch (Throwable $e) {
        throw new RuntimeException('published state has invalid published_at');
    }

    $publisherHash = receiptPublisherArticleHash($article);
    $stateHash = strtolower(trim((string) ($entry['content_hash'] ?? '')));
    if (!preg_match('/^[a-f0-9]{64}$/', $stateHash) || !hash_equals($stateHash, $publisherHash)) {
        throw new RuntimeException('publisher state content_hash does not match scheduled article bytes');
    }

    $publishedUrl = $baseUrl . '/index.php?c=show&id=' . $cmsId;
    $receipt = [
        'schema_version' => 1,
        'receipt_type' => 'publication_receipt',
        'article_id' => $articleId,
        'article_key' => $articleKey,
        'fingerprint' => $fingerprint,
        'content_hash' => $contentHash,
        'cms_id' => $cmsId,
        'published_url' => $publishedUrl,
        'published_at' => $publishedAt->format(DateTimeInterface::ATOM),
        'publisher_article_hash' => $publisherHash,
        'source_file' => basename($articlePath),
        'site_base_url' => $baseUrl,
    ];
    $receipt['receipt_id'] = receiptId($receipt);

    if ($outputPath !== '') {
        if (is_file($outputPath)) {
            $existing = receiptLoadJson($outputPath, 'existing publication receipt');
            if ((string) ($existing['receipt_id'] ?? '') === $receipt['receipt_id'] && $existing == $receipt) {
                fwrite(STDOUT, json_encode([
                    'status' => 'unchanged',
                    'receipt_id' => $receipt['receipt_id'],
                    'article_id' => $articleId,
                    'cms_id' => $cmsId,
                    'published_url' => $publishedUrl,
                    'output' => $outputPath,
                ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
                exit(0);
            }
            throw new RuntimeException('receipt output exists with different publication identity');
        }
        receiptAtomicWrite($outputPath, $receipt);
        fwrite(STDOUT, json_encode([
            'status' => 'receipt_created',
            'receipt_id' => $receipt['receipt_id'],
            'article_id' => $articleId,
            'cms_id' => $cmsId,
            'published_url' => $publishedUrl,
            'output' => $outputPath,
        ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
        exit(0);
    }

    fwrite(STDOUT, json_encode($receipt, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
} catch (Throwable $e) {
    receiptFail($e->getMessage());
}

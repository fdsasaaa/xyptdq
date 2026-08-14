#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/live_publication_seo.php';

function liveSeoFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[live-publication-seo] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function liveSeoReadJson(string $path): array
{
    if (!is_file($path)) {
        throw new RuntimeException('receipt not found: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data) || json_last_error() !== JSON_ERROR_NONE) {
        throw new RuntimeException('receipt is invalid JSON');
    }
    return $data;
}

function liveSeoAssertSiteUrl(string $url): void
{
    $parts = parse_url($url);
    $host = is_array($parts) ? strtolower((string) ($parts['host'] ?? '')) : '';
    if (!is_array($parts) || ($parts['scheme'] ?? '') !== 'https' || !in_array($host, ['laocaimi.org', 'www.laocaimi.org'], true)) {
        throw new RuntimeException('URL must be HTTPS laocaimi.org');
    }
    if (!empty($parts['user']) || !empty($parts['pass']) || !empty($parts['fragment'])) {
        throw new RuntimeException('URL must not contain credentials or fragment');
    }
}

function liveSeoCurl(string $url, string $bodyPath, string $headerPath): array
{
    liveSeoAssertSiteUrl($url);
    $format = '%{http_code}\n%{url_effective}';
    $cmd = 'curl -sS -L --max-time 30 --connect-timeout 10'
        . ' -D ' . escapeshellarg($headerPath)
        . ' -o ' . escapeshellarg($bodyPath)
        . ' -w ' . escapeshellarg($format)
        . ' --url ' . escapeshellarg($url);
    $out = [];
    $code = 0;
    exec($cmd . ' 2>&1', $out, $code);
    if ($code !== 0) {
        throw new RuntimeException('curl failed for site URL');
    }
    $http = isset($out[0]) ? (int) trim((string) $out[0]) : 0;
    $effective = isset($out[1]) ? trim((string) $out[1]) : '';
    if ($http <= 0 || $effective === '') {
        throw new RuntimeException('curl did not return HTTP/effective URL metadata');
    }
    return [$http, $effective];
}

$options = getopt('', [
    'receipt:',
    'sitemap-url::',
    'html-file::',
    'headers-file::',
    'sitemap-file::',
    'http-code::',
    'effective-url::',
]);
$receiptPath = (string) ($options['receipt'] ?? '');
if ($receiptPath === '') {
    liveSeoFail('Usage: php verify_publication_seo.php --receipt=receipt.json [--sitemap-url=https://www.laocaimi.org/sitemap.xml]');
}

try {
    $receipt = liveSeoReadJson($receiptPath);
    $receiptCheck = xyptdqValidatePublicationReceipt($receipt);
    if (!$receiptCheck['passed']) {
        throw new RuntimeException('invalid publication receipt: ' . implode('; ', $receiptCheck['errors']));
    }
    $publishedUrl = (string) $receiptCheck['published_url'];
    $sitemapUrl = (string) ($options['sitemap-url'] ?? 'https://www.laocaimi.org/sitemap.xml');
    liveSeoAssertSiteUrl($sitemapUrl);

    $htmlFile = (string) ($options['html-file'] ?? '');
    $headersFile = (string) ($options['headers-file'] ?? '');
    $sitemapFile = (string) ($options['sitemap-file'] ?? '');
    $offline = $htmlFile !== '' || $sitemapFile !== '';

    if ($offline) {
        if ($htmlFile === '' || $sitemapFile === '') {
            throw new RuntimeException('offline mode requires both --html-file and --sitemap-file');
        }
        if (!is_file($htmlFile) || !is_file($sitemapFile)) {
            throw new RuntimeException('offline HTML/Sitemap fixture missing');
        }
        $html = (string) file_get_contents($htmlFile);
        $sitemap = (string) file_get_contents($sitemapFile);
        $headers = $headersFile !== '' && is_file($headersFile) ? (string) file_get_contents($headersFile) : '';
        $httpCode = (int) ($options['http-code'] ?? 200);
        $effectiveUrl = (string) ($options['effective-url'] ?? $publishedUrl);
    } else {
        $tmpDir = sys_get_temp_dir() . '/xyptdq-live-seo-' . getmypid();
        if (!mkdir($tmpDir, 0700, true) && !is_dir($tmpDir)) {
            throw new RuntimeException('cannot create temporary verification directory');
        }
        try {
            $htmlPath = $tmpDir . '/page.html';
            $headersPath = $tmpDir . '/page.headers';
            $sitemapPath = $tmpDir . '/sitemap.xml';
            $sitemapHeadersPath = $tmpDir . '/sitemap.headers';
            [$httpCode, $effectiveUrl] = liveSeoCurl($publishedUrl, $htmlPath, $headersPath);
            [$sitemapCode] = liveSeoCurl($sitemapUrl, $sitemapPath, $sitemapHeadersPath);
            if ($sitemapCode !== 200) {
                throw new RuntimeException('Sitemap HTTP status is not 200');
            }
            $html = (string) file_get_contents($htmlPath);
            $headers = (string) file_get_contents($headersPath);
            $sitemap = (string) file_get_contents($sitemapPath);
        } finally {
            foreach (glob($tmpDir . '/*') ?: [] as $path) {
                @unlink($path);
            }
            @rmdir($tmpDir);
        }
    }

    $result = xyptdqVerifyPublishedSeo($receipt, $html, $sitemap, $httpCode, $effectiveUrl, $headers);
    fwrite(STDOUT, json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
    if (!$result['passed']) {
        exit(3);
    }
} catch (Throwable $e) {
    liveSeoFail($e->getMessage(), 1);
}

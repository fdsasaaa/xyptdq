#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/live_publication_seo.php';

function liveSeoTestFail(string $message): void
{
    fwrite(STDERR, '[live-publication-seo-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

$url = 'https://www.laocaimi.org/index.php?c=show&id=123';
$receipt = [
    'schema_version' => 1,
    'receipt_type' => 'publication_receipt',
    'article_id' => 'TEST-LIVE-001',
    'article_key' => 'test-live-001',
    'fingerprint' => str_repeat('a', 64),
    'content_hash' => str_repeat('b', 64),
    'cms_id' => 123,
    'published_url' => $url,
    'published_at' => '2026-08-14T00:00:00+00:00',
    'publisher_article_hash' => str_repeat('c', 64),
    'source_file' => 'test-live-001.json',
    'site_base_url' => 'https://www.laocaimi.org',
    'receipt_id' => str_repeat('d', 64),
];

$html = '<!doctype html><html><head>'
    . '<title>Generic published page</title>'
    . '<meta name="description" content="A generic published page used only for SEO verification tests.">'
    . '<meta name="robots" content="index,follow,max-image-preview:large">'
    . '<link rel="canonical" href="' . $url . '">'
    . '</head><body><main><h1>Generic published page</h1><p>Test content.</p></main></body></html>';
$sitemap = '<?xml version="1.0" encoding="UTF-8"?>'
    . '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
    . '<url><loc>' . htmlspecialchars($url, ENT_XML1 | ENT_QUOTES, 'UTF-8') . '</loc></url>'
    . '</urlset>';
$headers = "HTTP/2 200\r\nContent-Type: text/html; charset=UTF-8\r\n";

$valid = xyptdqVerifyPublishedSeo($receipt, $html, $sitemap, 200, $url, $headers);
if (!$valid['passed']) {
    liveSeoTestFail('valid page rejected: ' . implode(',', $valid['failed_checks']));
}

$badCanonicalHtml = str_replace($url, 'https://www.laocaimi.org/index.php?c=show&id=999', $html);
$badCanonical = xyptdqVerifyPublishedSeo($receipt, $badCanonicalHtml, $sitemap, 200, $url, $headers);
if ($badCanonical['passed'] || !in_array('single_self_canonical', $badCanonical['failed_checks'], true)) {
    liveSeoTestFail('canonical mismatch did not fail closed');
}

$noindexHtml = str_replace('index,follow,max-image-preview:large', 'noindex,follow', $html);
$noindex = xyptdqVerifyPublishedSeo($receipt, $noindexHtml, $sitemap, 200, $url, $headers);
if ($noindex['passed'] || !in_array('indexable_no_noindex', $noindex['failed_checks'], true)) {
    liveSeoTestFail('meta noindex did not fail closed');
}

$xRobots = xyptdqVerifyPublishedSeo($receipt, $html, $sitemap, 200, $url, "HTTP/2 200\r\nX-Robots-Tag: noindex\r\n");
if ($xRobots['passed'] || !in_array('indexable_no_noindex', $xRobots['failed_checks'], true)) {
    liveSeoTestFail('X-Robots-Tag noindex did not fail closed');
}

$missingSitemap = xyptdqVerifyPublishedSeo($receipt, $html, '<urlset></urlset>', 200, $url, $headers);
if ($missingSitemap['passed'] || !in_array('sitemap_membership', $missingSitemap['failed_checks'], true)) {
    liveSeoTestFail('missing Sitemap membership did not fail closed');
}

$redirectDrift = xyptdqVerifyPublishedSeo($receipt, $html, $sitemap, 200, 'https://www.laocaimi.org/index.php?c=show&id=124', $headers);
if ($redirectDrift['passed'] || !in_array('effective_url_exact', $redirectDrift['failed_checks'], true)) {
    liveSeoTestFail('effective URL drift did not fail closed');
}

fwrite(STDOUT, "[live-publication-seo-test] PASS http=guarded canonical=guarded noindex=guarded sitemap=guarded effective_url=guarded\n");

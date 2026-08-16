#!/usr/bin/env php
<?php
/**
 * XML-aware Sitemap membership check shared by production diagnostics.
 *
 * Raw string grep is incorrect for URLs containing query separators because
 * valid XML serializes `&` as `&amp;`. This wrapper reuses the canonical live
 * SEO parser, which decodes XML entities before normalizing and comparing URLs.
 */
declare(strict_types=1);

require __DIR__ . '/lib/live_publication_seo.php';

if ($argc !== 3) {
    fwrite(STDERR, "Usage: php sitemap_contains_url.php <sitemap.xml> <expected-url>\n");
    exit(2);
}

$path = (string) $argv[1];
$expectedUrl = (string) $argv[2];
if (!is_file($path)) {
    fwrite(STDERR, "Sitemap file not found\n");
    exit(2);
}

$xml = file_get_contents($path);
if ($xml === false) {
    fwrite(STDERR, "Sitemap file could not be read\n");
    exit(2);
}

if (xyptdqSitemapContainsUrl((string) $xml, $expectedUrl)) {
    fwrite(STDOUT, "SITEMAP_URL_PRESENT\n");
    exit(0);
}

fwrite(STDOUT, "SITEMAP_URL_ABSENT\n");
exit(1);

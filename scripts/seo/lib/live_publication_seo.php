<?php
/**
 * Read-only SEO checks for a published article page.
 * No CMS, Publisher, queue, Sitemap, or receipt state is modified here.
 */
declare(strict_types=1);

function xyptdqSeoAttr(string $tag, string $name): string
{
    $pattern = '/\b' . preg_quote($name, '/') . '\s*=\s*(["\'])(.*?)\1/is';
    if (!preg_match($pattern, $tag, $match)) {
        return '';
    }
    return trim(html_entity_decode((string) $match[2], ENT_QUOTES | ENT_HTML5, 'UTF-8'));
}

function xyptdqSeoText(string $html): string
{
    $text = strip_tags($html);
    $text = html_entity_decode($text, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    return trim((string) preg_replace('/\s+/u', ' ', $text));
}

function xyptdqSeoNormalizeUrl(string $url): string
{
    $url = trim($url);
    if ($url === '') {
        return '';
    }
    $parts = parse_url($url);
    if (!is_array($parts)) {
        return $url;
    }
    $scheme = strtolower((string) ($parts['scheme'] ?? ''));
    $host = strtolower((string) ($parts['host'] ?? ''));
    $port = isset($parts['port']) ? ':' . (int) $parts['port'] : '';
    $path = (string) ($parts['path'] ?? '');
    $query = isset($parts['query']) && $parts['query'] !== '' ? '?' . $parts['query'] : '';
    return ($scheme !== '' ? $scheme . '://' : '') . $host . $port . $path . $query;
}

function xyptdqValidatePublicationReceipt(array $receipt): array
{
    $errors = [];
    if ((int) ($receipt['schema_version'] ?? 0) !== 1) {
        $errors[] = 'receipt schema_version must be 1';
    }
    if (($receipt['receipt_type'] ?? null) !== 'publication_receipt') {
        $errors[] = 'receipt_type must be publication_receipt';
    }
    $cmsId = (int) ($receipt['cms_id'] ?? 0);
    if ($cmsId <= 0) {
        $errors[] = 'receipt cms_id must be positive';
    }
    $url = trim((string) ($receipt['published_url'] ?? ''));
    $parts = parse_url($url);
    $host = is_array($parts) ? strtolower((string) ($parts['host'] ?? '')) : '';
    if (!is_array($parts) || ($parts['scheme'] ?? '') !== 'https' || !in_array($host, ['laocaimi.org', 'www.laocaimi.org'], true)) {
        $errors[] = 'published_url must be HTTPS laocaimi.org';
    } else {
        parse_str((string) ($parts['query'] ?? ''), $query);
        if (($parts['path'] ?? '') !== '/index.php' || ($query['c'] ?? '') !== 'show' || (int) ($query['id'] ?? 0) !== $cmsId) {
            $errors[] = 'published_url does not match canonical show URL for cms_id';
        }
    }
    foreach (['article_id', 'article_key', 'fingerprint', 'content_hash', 'receipt_id'] as $field) {
        if (trim((string) ($receipt[$field] ?? '')) === '') {
            $errors[] = 'receipt missing ' . $field;
        }
    }
    return ['passed' => count($errors) === 0, 'errors' => $errors, 'published_url' => $url, 'cms_id' => $cmsId];
}

function xyptdqAnalyzePublishedHtml(string $html, string $expectedUrl, string $headers = ''): array
{
    $titles = [];
    if (preg_match_all('/<title\b[^>]*>(.*?)<\/title\s*>/is', $html, $matches)) {
        foreach ($matches[1] as $raw) {
            $titles[] = xyptdqSeoText((string) $raw);
        }
    }

    $h1s = [];
    if (preg_match_all('/<h1\b[^>]*>(.*?)<\/h1\s*>/is', $html, $matches)) {
        foreach ($matches[1] as $raw) {
            $h1s[] = xyptdqSeoText((string) $raw);
        }
    }

    $canonicals = [];
    if (preg_match_all('/<link\b[^>]*>/is', $html, $matches)) {
        foreach ($matches[0] as $tag) {
            $rel = strtolower(xyptdqSeoAttr((string) $tag, 'rel'));
            if (in_array('canonical', preg_split('/\s+/', $rel, -1, PREG_SPLIT_NO_EMPTY) ?: [], true)) {
                $canonicals[] = xyptdqSeoAttr((string) $tag, 'href');
            }
        }
    }

    $descriptions = [];
    $robotsValues = [];
    if (preg_match_all('/<meta\b[^>]*>/is', $html, $matches)) {
        foreach ($matches[0] as $tag) {
            $name = strtolower(xyptdqSeoAttr((string) $tag, 'name'));
            if ($name === 'description') {
                $descriptions[] = xyptdqSeoAttr((string) $tag, 'content');
            } elseif ($name === 'robots' || $name === 'googlebot') {
                $robotsValues[] = strtolower(xyptdqSeoAttr((string) $tag, 'content'));
            }
        }
    }

    $noindex = false;
    foreach ($robotsValues as $value) {
        if (preg_match('/(^|[,\s])noindex([,\s]|$)/i', $value)) {
            $noindex = true;
            break;
        }
    }
    if (!$noindex && $headers !== '' && preg_match('/^X-Robots-Tag\s*:\s*[^\r\n]*\bnoindex\b/im', $headers)) {
        $noindex = true;
    }

    $expectedNormalized = xyptdqSeoNormalizeUrl($expectedUrl);
    $canonicalExact = count($canonicals) === 1 && xyptdqSeoNormalizeUrl((string) $canonicals[0]) === $expectedNormalized;

    return [
        'title_count' => count($titles),
        'title_length' => count($titles) === 1 ? mb_strlen($titles[0], 'UTF-8') : 0,
        'h1_count' => count($h1s),
        'h1_length' => count($h1s) === 1 ? mb_strlen($h1s[0], 'UTF-8') : 0,
        'description_count' => count($descriptions),
        'description_length' => count($descriptions) === 1 ? mb_strlen(trim((string) $descriptions[0]), 'UTF-8') : 0,
        'canonical_count' => count($canonicals),
        'canonical_exact' => $canonicalExact,
        'noindex_detected' => $noindex,
    ];
}

function xyptdqSitemapContainsUrl(string $xml, string $expectedUrl): bool
{
    $expected = xyptdqSeoNormalizeUrl($expectedUrl);
    if ($expected === '') {
        return false;
    }
    if (!preg_match_all('/<loc\b[^>]*>(.*?)<\/loc\s*>/is', $xml, $matches)) {
        return false;
    }
    foreach ($matches[1] as $raw) {
        $url = html_entity_decode(trim(strip_tags((string) $raw)), ENT_QUOTES | ENT_XML1, 'UTF-8');
        if (xyptdqSeoNormalizeUrl($url) === $expected) {
            return true;
        }
    }
    return false;
}

function xyptdqVerifyPublishedSeo(array $receipt, string $html, string $sitemapXml, int $httpCode, string $effectiveUrl, string $headers = ''): array
{
    $receiptCheck = xyptdqValidatePublicationReceipt($receipt);
    $expectedUrl = (string) $receiptCheck['published_url'];
    $page = xyptdqAnalyzePublishedHtml($html, $expectedUrl, $headers);
    $checks = [
        'receipt_valid' => $receiptCheck['passed'],
        'http_200' => $httpCode === 200,
        'effective_url_exact' => xyptdqSeoNormalizeUrl($effectiveUrl) === xyptdqSeoNormalizeUrl($expectedUrl),
        'single_nonempty_title' => $page['title_count'] === 1 && $page['title_length'] > 0,
        'single_nonempty_h1' => $page['h1_count'] === 1 && $page['h1_length'] > 0,
        'single_nonempty_description' => $page['description_count'] === 1 && $page['description_length'] > 0,
        'single_self_canonical' => $page['canonical_count'] === 1 && $page['canonical_exact'] === true,
        'indexable_no_noindex' => $page['noindex_detected'] === false,
        'sitemap_membership' => xyptdqSitemapContainsUrl($sitemapXml, $expectedUrl),
    ];
    $failed = [];
    foreach ($checks as $name => $passed) {
        if (!$passed) {
            $failed[] = $name;
        }
    }
    return [
        'passed' => count($failed) === 0,
        'article_id' => (string) ($receipt['article_id'] ?? ''),
        'cms_id' => (int) ($receipt['cms_id'] ?? 0),
        'published_url' => $expectedUrl,
        'checks' => $checks,
        'failed_checks' => $failed,
        'page_metrics' => $page,
        'receipt_errors' => $receiptCheck['errors'],
    ];
}

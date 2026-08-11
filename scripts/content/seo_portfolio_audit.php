#!/usr/bin/env php
<?php
declare(strict_types=1);

const SEO_PORTFOLIO_LEGACY_SCHEDULED_EXEMPT = [
    'seo-ffc-betting-economics-v1',
    'seo-ffc-drawdown-vs-losing-streak-v1',
    'seo-ffc-high-hit-not-profit-v1',
    'seo-ffc-losing-streak-cumulative-loss-v1',
    'seo-ffc-method-cost-compare-v1',
    'seo-ffc-payout-and-cost-v1',
    'seo-ffc-rebate-accounting-v1',
    'seo-ffc-risk-budget-before-multiplier-v1',
    'seo-ffc-six-economic-parameters-v1',
    'seo-ffc-stop-rules-v1',
    'seo-ffc-theoretical-hit-rate-v1',
];

function seoAuditFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[seo-portfolio] FAIL: ' . $message . PHP_EOL);
    exit($code);
}

function seoNormalizeKeyword(string $value): string
{
    $value = preg_replace('/\s+/u', '', trim($value));
    return mb_strtolower((string) $value, 'UTF-8');
}

$options = getopt('', ['root::']);
$repoRoot = dirname(__DIR__, 2);
$contentRoot = $options['root'] ?? ($repoRoot . '/content');
$locations = [
    'drafts' => 'draft',
    'scheduled' => 'scheduled',
];

$keywordOwners = [];
$articleKeywords = [];
$articleFingerprints = [];
$fileCount = 0;
$managedFileCount = 0;
$legacyExemptCount = 0;
$stateCounts = ['draft' => 0, 'scheduled' => 0];

foreach ($locations as $dirName => $expectedState) {
    $dir = rtrim($contentRoot, '/\\') . '/' . $dirName;
    if (!is_dir($dir)) {
        continue;
    }
    foreach (glob($dir . '/*.json') ?: [] as $path) {
        $fileCount++;
        $raw = (string) file_get_contents($path);
        $row = json_decode($raw, true);
        if (!is_array($row) || json_last_error() !== JSON_ERROR_NONE) {
            seoAuditFail('invalid JSON: ' . $path, 2);
        }

        $articleKey = trim((string) ($row['article_key'] ?? ''));
        $state = trim((string) ($row['publication_state'] ?? ''));
        $articleId = trim((string) ($row['source_article_id'] ?? ''));

        // These exact article keys were committed before the Approved-Package
        // bridge existed. They lack provenance fields that cannot be reconstructed
        // without inventing history. This is a closed manifest: prefixes, missing
        // fields, or directory placement alone never grant exemption.
        if (
            $expectedState === 'scheduled'
            && in_array($articleKey, SEO_PORTFOLIO_LEGACY_SCHEDULED_EXEMPT, true)
            && $state === ''
            && $articleId === ''
        ) {
            if (basename($path, '.json') !== $articleKey) {
                seoAuditFail('legacy exempt article_key/path mismatch: ' . $path, 13);
            }
            if (trim((string) ($row['publish_at'] ?? '')) === '') {
                seoAuditFail('legacy scheduled exempt missing publish_at: ' . $path, 14);
            }
            if (trim((string) ($row['primary_keyword'] ?? '')) === '') {
                seoAuditFail('legacy scheduled exempt missing primary_keyword: ' . $path, 15);
            }
            $legacyExemptCount++;
            continue;
        }

        $managedFileCount++;
        if ($state !== $expectedState) {
            seoAuditFail('publication_state/path mismatch: ' . $path, 3);
        }
        $stateCounts[$expectedState]++;

        $keywordRaw = trim((string) ($row['primary_keyword'] ?? ''));
        $fingerprint = trim((string) ($row['source_fingerprint'] ?? ''));
        $content = (string) ($row['content'] ?? '');
        $storedHash = trim((string) ($row['source_content_hash'] ?? ''));
        if ($articleId === '') {
            seoAuditFail('source_article_id missing: ' . $path, 4);
        }
        if ($keywordRaw === '') {
            seoAuditFail('primary_keyword missing: ' . $path, 5);
        }
        if ($fingerprint === '') {
            seoAuditFail('source_fingerprint missing: ' . $path, 6);
        }
        if ($storedHash === '' || !hash_equals($storedHash, hash('sha256', $content))) {
            seoAuditFail('source_content_hash mismatch: ' . $path, 7);
        }
        if ($expectedState === 'draft' && array_key_exists('publish_at', $row) && trim((string) ($row['publish_at'] ?? '')) !== '') {
            seoAuditFail('draft unexpectedly has publish_at: ' . $path, 8);
        }
        if ($expectedState === 'scheduled' && trim((string) ($row['publish_at'] ?? '')) === '') {
            seoAuditFail('scheduled item missing publish_at: ' . $path, 9);
        }

        $keyword = seoNormalizeKeyword($keywordRaw);
        $keywordOwners[$keyword][$articleId][] = $path;
        $articleKeywords[$articleId][$keyword] = $keywordRaw;
        $articleFingerprints[$articleId][$fingerprint] = true;
    }
}

foreach ($articleKeywords as $articleId => $keywords) {
    if (count($keywords) > 1) {
        seoAuditFail('same article has keyword drift across states: ' . $articleId . ' -> ' . implode(', ', array_values($keywords)), 10);
    }
}
foreach ($articleFingerprints as $articleId => $fingerprints) {
    if (count($fingerprints) > 1) {
        seoAuditFail('same article has fingerprint drift across states: ' . $articleId, 11);
    }
}
foreach ($keywordOwners as $keyword => $owners) {
    if (count($owners) > 1) {
        seoAuditFail('exact primary_keyword has multiple article owners: ' . $keyword . ' -> ' . implode(', ', array_keys($owners)), 12);
    }
}

fwrite(STDOUT, json_encode([
    'status' => 'pass',
    'files' => $fileCount,
    'managed_files' => $managedFileCount,
    'legacy_exempt' => $legacyExemptCount,
    'drafts' => $stateCounts['draft'],
    'scheduled' => $stateCounts['scheduled'],
    'article_owners' => count($articleKeywords),
    'keyword_owners' => count($keywordOwners),
    'keyword_conflicts' => 0,
], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);

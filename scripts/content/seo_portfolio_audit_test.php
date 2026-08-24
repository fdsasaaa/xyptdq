#!/usr/bin/env php
<?php
declare(strict_types=1);

$audit = __DIR__ . '/seo_portfolio_audit.php';
$tmpBase = sys_get_temp_dir() . '/xyptdq-seo-portfolio-' . getmypid();

function portfolioTestFail(string $message): void
{
    fwrite(STDERR, '[seo-portfolio-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function portfolioReset(string $root): void
{
    if (is_dir($root)) {
        foreach (['drafts', 'scheduled'] as $dirName) {
            $dir = $root . '/' . $dirName;
            foreach (glob($dir . '/*.json') ?: [] as $file) {
                @unlink($file);
            }
            @rmdir($dir);
        }
        @rmdir($root);
    }
    foreach (['drafts', 'scheduled'] as $dirName) {
        $dir = $root . '/' . $dirName;
        if (!mkdir($dir, 0750, true) && !is_dir($dir)) {
            portfolioTestFail('cannot create fixture directory: ' . $dir);
        }
    }
}

function portfolioRow(
    string $articleId,
    string $keyword,
    string $fingerprint,
    string $state = 'draft',
    string $content = '<p>fixture article content</p>'
): array {
    $row = [
        'schema_version' => 1,
        'article_key' => strtolower(str_replace('_', '-', $articleId)),
        'title' => '测试文章标题-' . $articleId,
        'content' => $content,
        'primary_keyword' => $keyword,
        'publication_state' => $state,
        'source_article_id' => $articleId,
        'source_fingerprint' => $fingerprint,
        'source_content_hash' => hash('sha256', $content),
    ];
    if ($state === 'scheduled') {
        $row['publish_at'] = '2026-08-12T09:00:00+08:00';
    }
    return $row;
}

function legacyScheduledRow(string $articleKey): array
{
    return [
        'schema_version' => 1,
        'article_key' => $articleKey,
        'title' => '桥梁建立前的历史排期内容',
        'content' => '<p>legacy scheduled fixture</p>',
        'primary_keyword' => '分分彩投注技巧',
        'publish_at' => '2026-08-11T07:15:00+08:00',
    ];
}

function portfolioWrite(string $root, string $bucket, string $name, array $row): void
{
    $path = $root . '/' . $bucket . '/' . $name . '.json';
    $json = json_encode($row, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($path, $json . PHP_EOL) === false) {
        portfolioTestFail('cannot write fixture: ' . $path);
    }
}

function portfolioRun(string $audit, string $root): array
{
    $lines = [];
    $code = 0;
    $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($audit) . ' --root=' . escapeshellarg($root);
    exec($cmd . ' 2>&1', $lines, $code);
    return ['code' => $code, 'output' => implode("\n", $lines)];
}

try {
    // Unique article owners pass.
    portfolioReset($tmpBase);
    portfolioWrite($tmpBase, 'drafts', 'a', portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('a', 64)));
    portfolioWrite($tmpBase, 'drafts', 'b', portfolioRow('B', '分分彩定位胆遗漏技巧', str_repeat('b', 64)));
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] !== 0 || strpos($run['output'], '"keyword_conflicts": 0') === false || strpos($run['output'], '"title_conflicts": 0') === false) {
        portfolioTestFail('unique draft owners should pass: ' . $run['output']);
    }

    // The exact historical pre-bridge canary may remain unmanaged; this is a named grandfather, not a generic bypass.
    portfolioReset($tmpBase);
    portfolioWrite($tmpBase, 'scheduled', 'seo-ffc-betting-economics-v1', legacyScheduledRow('seo-ffc-betting-economics-v1'));
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] !== 0 || strpos($run['output'], '"legacy_exempt": 1') === false) {
        portfolioTestFail('known legacy scheduled canary should be explicitly grandfathered: ' . $run['output']);
    }

    // Any other unmanaged scheduled file is rejected; omitting bridge identity cannot bypass the audit.
    portfolioReset($tmpBase);
    portfolioWrite($tmpBase, 'scheduled', 'unknown-legacy', legacyScheduledRow('unknown-legacy'));
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] === 0 || strpos($run['output'], 'publication_state/path mismatch') === false) {
        portfolioTestFail('unknown unmanaged scheduled file escaped the audit');
    }

    // The same article may legitimately exist as both draft and scheduled if identity/SEO is identical.
    portfolioReset($tmpBase);
    $draft = portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('a', 64));
    portfolioWrite($tmpBase, 'drafts', 'a', $draft);
    $scheduled = $draft;
    $scheduled['publication_state'] = 'scheduled';
    $scheduled['publish_at'] = '2026-08-12T09:00:00+08:00';
    portfolioWrite($tmpBase, 'scheduled', 'a', $scheduled);
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] !== 0 || strpos($run['output'], '"article_owners": 1') === false) {
        portfolioTestFail('same article across draft/scheduled should pass: ' . $run['output']);
    }

    // Unicode/ordinary whitespace normalization must not allow two articles to own the same exact keyword.
    portfolioReset($tmpBase);
    portfolioWrite($tmpBase, 'drafts', 'a', portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('a', 64)));
    portfolioWrite($tmpBase, 'drafts', 'b', portfolioRow('B', '分分彩 定位胆冷热技巧', str_repeat('b', 64)));
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] === 0 || strpos($run['output'], 'multiple article owners') === false) {
        portfolioTestFail('different articles sharing normalized keyword were not rejected');
    }

    // One article cannot drift to a different primary keyword when copied to scheduled.
    portfolioReset($tmpBase);
    portfolioWrite($tmpBase, 'drafts', 'a', portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('a', 64)));
    portfolioWrite($tmpBase, 'scheduled', 'a', portfolioRow('A', '分分彩定位胆遗漏技巧', str_repeat('a', 64), 'scheduled'));
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] === 0 || strpos($run['output'], 'keyword drift') === false) {
        portfolioTestFail('same-article keyword drift was not rejected');
    }

    // One article cannot drift to another fingerprint across states.
    portfolioReset($tmpBase);
    portfolioWrite($tmpBase, 'drafts', 'a', portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('a', 64)));
    portfolioWrite($tmpBase, 'scheduled', 'a', portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('b', 64), 'scheduled'));
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] === 0 || strpos($run['output'], 'fingerprint drift') === false) {
        portfolioTestFail('same-article fingerprint drift was not rejected');
    }

    // Broad site keywords are owned by home/category/hub targets, never by an article Draft.
    portfolioReset($tmpBase);
    portfolioWrite($tmpBase, 'drafts', 'a', portfolioRow('A', '分分彩技巧', str_repeat('a', 64)));
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] === 0 || strpos($run['output'], 'reserved site target') === false) {
        portfolioTestFail('reserved broad site keyword was not rejected');
    }

    // Different articles cannot use the same normalized human title even if primary keywords differ.
    portfolioReset($tmpBase);
    $a = portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('a', 64));
    $b = portfolioRow('B', '分分彩定位胆遗漏技巧', str_repeat('b', 64));
    $a['title'] = '先看规则，再看复核：定位胆怎么理解';
    $b['title'] = '先看规则再看复核，定位胆怎么理解';
    portfolioWrite($tmpBase, 'drafts', 'a', $a);
    portfolioWrite($tmpBase, 'drafts', 'b', $b);
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] === 0 || strpos($run['output'], 'normalized title has multiple article owners') === false) {
        portfolioTestFail('different articles sharing normalized title were not rejected');
    }

    // Stored content hash must still prove the actual content bytes.
    portfolioReset($tmpBase);
    $tampered = portfolioRow('A', '分分彩定位胆冷热技巧', str_repeat('a', 64));
    $tampered['source_content_hash'] = str_repeat('0', 64);
    portfolioWrite($tmpBase, 'drafts', 'a', $tampered);
    $run = portfolioRun($audit, $tmpBase);
    if ($run['code'] === 0 || strpos($run['output'], 'source_content_hash mismatch') === false) {
        portfolioTestFail('tampered content hash was not rejected');
    }
} finally {
    portfolioReset($tmpBase);
    foreach (['drafts', 'scheduled'] as $dirName) {
        @rmdir($tmpBase . '/' . $dirName);
    }
    @rmdir($tmpBase);
}

fwrite(STDOUT, "[seo-portfolio-test] PASS unique=1 named-legacy-exempt=1 unknown-legacy=blocked same-article-cross-state=1 keyword-conflict=blocked keyword-drift=blocked fingerprint-drift=blocked reserved-keyword=blocked title-conflict=blocked hash-tamper=blocked\n");

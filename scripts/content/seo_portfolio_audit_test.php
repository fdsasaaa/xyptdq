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
    if ($run['code'] !== 0 || strpos($run['output'], '"keyword_conflicts": 0') === false) {
        portfolioTestFail('unique draft owners should pass: ' . $run['output']);
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

fwrite(STDOUT, "[seo-portfolio-test] PASS unique=1 same-article-cross-state=1 keyword-conflict=blocked keyword-drift=blocked fingerprint-drift=blocked hash-tamper=blocked\n");

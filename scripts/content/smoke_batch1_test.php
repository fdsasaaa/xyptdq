#!/usr/bin/env php
<?php
declare(strict_types=1);

$repoRoot = dirname(__DIR__, 2);
$converter = __DIR__ . '/convert_approved_to_draft.php';
$cases = [
    'LCM-SMOKE-20260811-01' => 'lcm-smoke-20260811-01',
    'LCM-SMOKE-20260811-02' => 'lcm-smoke-20260811-02',
    'LCM-SMOKE-20260811-03' => 'lcm-smoke-20260811-03',
];

function smokeFail(string $message): void
{
    fwrite(STDERR, '[smoke-batch1] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function loadJson(string $path): array
{
    if (!is_file($path)) {
        smokeFail('missing file: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data)) {
        smokeFail('invalid JSON: ' . $path);
    }
    return $data;
}

$tmpRoot = sys_get_temp_dir() . '/xyptdq-smoke-batch1-' . getmypid();
if (!mkdir($tmpRoot, 0750, true) && !is_dir($tmpRoot)) {
    smokeFail('cannot create temp directory');
}

try {
    foreach ($cases as $articleId => $articleKey) {
        $input = $repoRoot . '/content/ingress/smoke-batch1/' . $articleId . '.json';
        $committedPath = $repoRoot . '/content/drafts/' . $articleKey . '.json';
        $generatedPath = $tmpRoot . '/' . $articleKey . '.json';

        $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
            . ' --input=' . escapeshellarg($input)
            . ' --output=' . escapeshellarg($generatedPath);
        $output = [];
        $code = 0;
        exec($cmd . ' 2>&1', $output, $code);
        if ($code !== 0) {
            smokeFail($articleId . ' converter failed: ' . implode("\n", $output));
        }

        $generated = loadJson($generatedPath);
        $committed = loadJson($committedPath);

        if (($generated['article_key'] ?? '') !== $articleKey) {
            smokeFail($articleId . ' unstable article_key');
        }
        if (($generated['publication_state'] ?? '') !== 'draft') {
            smokeFail($articleId . ' is not draft');
        }
        if ((int) ($generated['catid'] ?? 0) !== 3 || ($generated['site_category_key'] ?? '') !== 'tzjq') {
            smokeFail($articleId . ' category mapping is not tzjq/catid=3');
        }
        if (array_key_exists('publish_at', $generated) || array_key_exists('publish_at', $committed)) {
            smokeFail($articleId . ' draft unexpectedly contains publish_at');
        }
        if (($generated['source_content_hash'] ?? '') !== hash('sha256', (string) ($generated['content'] ?? ''))) {
            smokeFail($articleId . ' source content hash mismatch');
        }

        // converted_at is intentionally runtime-generated; every other converter field must match.
        unset($generated['converted_at'], $committed['converted_at']);
        if ($generated != $committed) {
            smokeFail($articleId . ' committed draft differs from converter output');
        }

        $scheduledPath = $repoRoot . '/content/scheduled/' . $articleKey . '.json';
        if (is_file($scheduledPath)) {
            smokeFail($articleId . ' unexpectedly exists in content/scheduled');
        }
    }
} finally {
    foreach (glob($tmpRoot . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmpRoot);
}

fwrite(STDOUT, "[smoke-batch1] PASS drafts=3 scheduled=0 published=0\n");

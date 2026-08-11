#!/usr/bin/env php
<?php
declare(strict_types=1);

$repoRoot = dirname(__DIR__, 2);
$converter = __DIR__ . '/convert_approved_to_draft.php';
$cases = [
    'LCM-IDEA-bf5a9864b004ae17' => 'lcm-idea-bf5a9864b004ae17',
    'LCM-IDEA-48eb8743fbbbad11' => 'lcm-idea-48eb8743fbbbad11',
    'LCM-IDEA-9ea1859cc88b2682' => 'lcm-idea-9ea1859cc88b2682',
    'LCM-IDEA-62bfa71c95642c9d' => 'lcm-idea-62bfa71c95642c9d',
    'LCM-IDEA-07838cdf108296a7' => 'lcm-idea-07838cdf108296a7',
];

function smoke2Fail(string $message): void
{
    fwrite(STDERR, '[smoke-batch2] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

function smoke2LoadJson(string $path): array
{
    if (!is_file($path)) {
        smoke2Fail('missing file: ' . $path);
    }
    $data = json_decode((string) file_get_contents($path), true);
    if (!is_array($data)) {
        smoke2Fail('invalid JSON: ' . $path);
    }
    return $data;
}

$tmpRoot = sys_get_temp_dir() . '/xyptdq-smoke-batch2-' . getmypid();
if (!mkdir($tmpRoot, 0750, true) && !is_dir($tmpRoot)) {
    smoke2Fail('cannot create temp directory');
}

try {
    foreach ($cases as $articleId => $articleKey) {
        $input = $repoRoot . '/content/ingress/smoke-batch2/' . $articleId . '.json';
        $committedPath = $repoRoot . '/content/drafts/' . $articleKey . '.json';
        $generatedPath = $tmpRoot . '/' . $articleKey . '.json';

        $cmd = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($converter)
            . ' --input=' . escapeshellarg($input)
            . ' --output=' . escapeshellarg($generatedPath);
        $output = [];
        $code = 0;
        exec($cmd . ' 2>&1', $output, $code);
        if ($code !== 0) {
            smoke2Fail($articleId . ' converter failed: ' . implode("\n", $output));
        }

        $inputPackage = smoke2LoadJson($input);
        $generated = smoke2LoadJson($generatedPath);
        $committed = smoke2LoadJson($committedPath);

        if (($generated['article_key'] ?? '') !== $articleKey) {
            smoke2Fail($articleId . ' unstable article_key');
        }
        if (($generated['publication_state'] ?? '') !== 'draft') {
            smoke2Fail($articleId . ' is not draft');
        }
        if ((int) ($generated['catid'] ?? 0) !== 3 || ($generated['site_category_key'] ?? '') !== 'tzjq') {
            smoke2Fail($articleId . ' category mapping is not tzjq/catid=3');
        }
        if (array_key_exists('publish_at', $generated) || array_key_exists('publish_at', $committed)) {
            smoke2Fail($articleId . ' draft unexpectedly contains publish_at');
        }
        $contentHash = hash('sha256', (string) ($generated['content'] ?? ''));
        if (($generated['source_content_hash'] ?? '') !== $contentHash) {
            smoke2Fail($articleId . ' generated source content hash mismatch');
        }
        if (($inputPackage['content_hash'] ?? '') !== $contentHash) {
            smoke2Fail($articleId . ' ingress content hash mismatch');
        }
        if (($generated['source_fingerprint'] ?? '') !== ($inputPackage['fingerprint'] ?? '')) {
            smoke2Fail($articleId . ' fingerprint was not preserved');
        }

        // converted_at is intentionally runtime-generated; every other converter field must match.
        unset($generated['converted_at'], $committed['converted_at']);
        if ($generated != $committed) {
            smoke2Fail($articleId . ' committed draft differs from converter output');
        }

        $scheduledPath = $repoRoot . '/content/scheduled/' . $articleKey . '.json';
        if (is_file($scheduledPath)) {
            smoke2Fail($articleId . ' unexpectedly exists in content/scheduled');
        }
    }
} finally {
    foreach (glob($tmpRoot . '/*.json') ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($tmpRoot);
}

fwrite(STDOUT, "[smoke-batch2] PASS drafts=5 scheduled=0 published=0\n");

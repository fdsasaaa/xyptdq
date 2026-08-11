#!/usr/bin/env php
<?php
/**
 * Validate and atomically stage one Approved Package into an external queue.
 * No CMS/database write occurs here.
 */
declare(strict_types=1);

require __DIR__ . '/lib/approved_package.php';

function stageFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[content-stage] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

if ($argc !== 2) {
    stageFail('Usage: php stage_approved_package.php <approved-package.json>', 64);
}

$queueRoot = getenv('XYPTDQ_CONTENT_QUEUE') ?: '/var/lib/xyptdq/content-queue';
$pendingDir = rtrim($queueRoot, '/') . '/pending';

try {
    $package = xyptdq_read_package_file($argv[1]);
    $validation = xyptdq_validate_approved_package($package);
    if (!$validation['passed']) {
        stageFail('package validation failed: ' . implode('; ', $validation['errors']), 2);
    }

    if (!is_dir($pendingDir) && !mkdir($pendingDir, 0750, true) && !is_dir($pendingDir)) {
        stageFail('unable to create pending queue directory: ' . $pendingDir, 3);
    }

    $articleId = (string) $package['article_id'];
    $contentHash = strtolower((string) ($package['content_hash'] ?? hash('sha256', (string) $package['content'])));
    $safeId = preg_replace('/[^A-Za-z0-9._-]+/', '_', $articleId);
    if (!is_string($safeId) || $safeId === '') {
        stageFail('unable to derive safe queue filename', 4);
    }

    $glob = glob($pendingDir . '/' . $safeId . '__*.json') ?: [];
    foreach ($glob as $existing) {
        $existingPackage = xyptdq_read_package_file($existing);
        $existingHash = strtolower((string) ($existingPackage['content_hash'] ?? hash('sha256', (string) ($existingPackage['content'] ?? ''))));
        if (hash_equals($existingHash, $contentHash)) {
            fwrite(STDOUT, json_encode([
                'status' => 'already_staged',
                'article_id' => $articleId,
                'content_hash' => $contentHash,
                'queue_file' => $existing,
                'warnings' => $validation['warnings'],
            ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
            exit(0);
        }
        stageFail('different content version for article_id is already pending; explicit resolution required', 5);
    }

    $package['content_hash'] = $contentHash;
    $package['bridge_status'] = 'pending_cms_draft';
    $package['staged_at'] = gmdate('c');
    $target = $pendingDir . '/' . $safeId . '__' . substr($contentHash, 0, 16) . '.json';
    $tmp = $target . '.tmp.' . getmypid();
    $json = json_encode($package, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        @unlink($tmp);
        stageFail('unable to write temporary queue file', 6);
    }
    @chmod($tmp, 0640);
    if (!rename($tmp, $target)) {
        @unlink($tmp);
        stageFail('unable to atomically stage package', 7);
    }

    fwrite(STDOUT, json_encode([
        'status' => 'staged',
        'article_id' => $articleId,
        'content_hash' => $contentHash,
        'queue_file' => $target,
        'warnings' => $validation['warnings'],
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
} catch (Throwable $e) {
    stageFail($e->getMessage(), 1);
}

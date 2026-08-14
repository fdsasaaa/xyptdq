#!/usr/bin/env php
<?php
declare(strict_types=1);

require __DIR__ . '/lib/public_release_package.php';

function intakeFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[public-release-intake] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function readJsonObject(string $path, string $label): array
{
    if (!is_file($path)) {
        throw new RuntimeException($label . ' file not found: ' . $path);
    }
    $payload = json_decode((string) file_get_contents($path), true);
    if (!is_array($payload) || json_last_error() !== JSON_ERROR_NONE) {
        throw new RuntimeException($label . ' is invalid JSON: ' . json_last_error_msg());
    }
    return $payload;
}

$options = getopt('', ['revision:', 'parent:', 'manifest:', 'mode::']);
$revisionPath = (string) ($options['revision'] ?? '');
$parentPath = (string) ($options['parent'] ?? '');
$manifestPath = (string) ($options['manifest'] ?? '');
$mode = strtolower(trim((string) ($options['mode'] ?? 'canary')));

if ($revisionPath === '' || $parentPath === '' || $manifestPath === '') {
    intakeFail('Usage: php validate_public_release_intake.php --revision=... --parent=... --manifest=... [--mode=canary|batch]', 2);
}

try {
    $revision = readJsonObject($revisionPath, 'revision');
    $parent = readJsonObject($parentPath, 'parent');
    $manifest = readJsonObject($manifestPath, 'manifest');
    $result = xyptdq_validate_public_release_intake($revision, $parent, $manifest, $mode);
    fwrite(STDOUT, json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . PHP_EOL);
    if (!$result['passed']) {
        exit(3);
    }
} catch (Throwable $e) {
    intakeFail($e->getMessage(), 1);
}

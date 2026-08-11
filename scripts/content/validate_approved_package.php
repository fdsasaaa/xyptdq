#!/usr/bin/env php
<?php
/** Validate one Approved Package JSON without writing CMS state. */
declare(strict_types=1);

require __DIR__ . '/lib/approved_package.php';

if ($argc !== 2) {
    fwrite(STDERR, "Usage: php validate_approved_package.php <approved-package.json>\n");
    exit(64);
}

try {
    $package = xyptdq_read_package_file($argv[1]);
    $result = xyptdq_validate_approved_package($package);
    $result['article_id'] = $package['article_id'] ?? null;
    $result['content_hash'] = $package['content_hash'] ?? hash('sha256', (string) ($package['content'] ?? ''));
    fwrite(STDOUT, json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
    exit($result['passed'] ? 0 : 2);
} catch (Throwable $e) {
    fwrite(STDERR, '[content-validator] ERROR: ' . $e->getMessage() . PHP_EOL);
    exit(1);
}

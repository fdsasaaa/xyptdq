#!/usr/bin/env php
<?php
declare(strict_types=1);

function isolationFail(string $message): void
{
    fwrite(STDERR, '[publisher-source-isolation-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

$script = __DIR__ . '/run_scheduled_publish.sh';
if (!is_file($script)) {
    isolationFail('publisher wrapper missing');
}
$src = (string) file_get_contents($script);

$required = [
    'SOURCE_QUEUE="${XYPTDQ_PUBLISH_SOURCE:-}"',
    'RUNTIME_QUEUE_ROOT="/var/lib/xyptdq-content"',
    'XYPTDQ_PUBLISH_SOURCE is required when publishing is enabled',
    'SOURCE_REAL=$(realpath "$SOURCE_QUEUE")',
    'ROOT_REAL=$(realpath "$RUNTIME_QUEUE_ROOT")',
    'LEGACY_REAL=$(realpath "$LEGACY_QUEUE")',
    'legacy repository Scheduled queue is forbidden',
    '--source="$SOURCE_QUEUE"',
];
foreach ($required as $needle) {
    if (strpos($src, $needle) === false) {
        isolationFail('missing fail-closed marker: ' . $needle);
    }
}

if (strpos($src, '--source="$REPO_DIR/content/scheduled"') !== false) {
    isolationFail('legacy repository Scheduled queue is still hard-coded as publisher source');
}

$policyPause = strpos($src, 'PAUSED by content publication policy');
$sourceGuard = strpos($src, 'XYPTDQ_PUBLISH_SOURCE is required when publishing is enabled');
if ($policyPause === false || $sourceGuard === false || $policyPause > $sourceGuard) {
    isolationFail('disabled publication policy must pause before isolated-source enforcement');
}

fwrite(STDOUT, "[publisher-source-isolation-test] PASS explicit_source=required legacy_queue=forbidden realpath=guarded policy_pause=preserved\n");

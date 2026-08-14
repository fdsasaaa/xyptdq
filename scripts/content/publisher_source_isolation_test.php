#!/usr/bin/env php
<?php
declare(strict_types=1);

function isolationFail(string $message): void
{
    fwrite(STDERR, '[publisher-source-isolation-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

$runner = __DIR__ . '/run_scheduled_publish.sh';
$installer = __DIR__ . '/install_publisher_cron.sh';
foreach ([$runner, $installer] as $path) {
    if (!is_file($path)) {
        isolationFail('required Publisher script missing: ' . basename($path));
    }
}
$src = (string) file_get_contents($runner);
$cron = (string) file_get_contents($installer);

$required = [
    'SOURCE_QUEUE="${XYPTDQ_PUBLISH_SOURCE:-}"',
    'RUNTIME_QUEUE_ROOT="/var/lib/xyptdq-content"',
    'XYPTDQ_PUBLISH_SOURCE is required when publishing is enabled',
    'SOURCE_REAL=$(realpath "$SOURCE_QUEUE")',
    'ROOT_REAL=$(realpath "$RUNTIME_QUEUE_ROOT")',
    'LEGACY_REAL=$(realpath "$LEGACY_QUEUE")',
    'legacy repository Scheduled queue is forbidden',
    '--source="$SOURCE_QUEUE"',
    'PUBLISH_TMP=$(mktemp /tmp/xyptdq-publish-output.',
    'export_publication_receipt.php',
    'verify_publication_seo.php',
    'SEO_VERIFY_PASS',
    'SEO_VERIFY_WARN',
    'seo_verification=$SEO_STATUS',
];
foreach ($required as $needle) {
    if (strpos($src, $needle) === false) {
        isolationFail('missing runner fail-closed/verification marker: ' . $needle);
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

$sitemapRefresh = strpos($src, 'scripts/seo/generate_sitemap.php');
$liveVerify = strpos($src, 'scripts/seo/verify_publication_seo.php');
if ($sitemapRefresh === false || $liveVerify === false || $sitemapRefresh > $liveVerify) {
    isolationFail('Sitemap refresh must occur before live SEO verification');
}
if (strpos($src, 'if php "$REPO_DIR/scripts/seo/verify_publication_seo.php"') === false) {
    isolationFail('live SEO verifier must be warning-gated rather than rolling back published CMS state');
}

$cronRequired = [
    'SOURCE_QUEUE="${XYPTDQ_PUBLISH_SOURCE:-}"',
    'STATE_PATH="${XYPTDQ_PUBLISH_STATE:-}"',
    'LOCK_PATH="${XYPTDQ_PUBLISH_LOCK:-}"',
    'QUEUE_ROOT="/var/lib/xyptdq-content"',
    'STATE_ROOT="/var/lib/xyptdq-publisher"',
    'XYPTDQ_PUBLISH_SOURCE is required',
    'XYPTDQ_PUBLISH_STATE is required',
    'XYPTDQ_PUBLISH_LOCK is required',
    'SOURCE_REAL=$(realpath "$SOURCE_QUEUE")',
    'STATE_PARENT=$(dirname "$STATE_PATH")',
    'LOCK_PARENT=$(dirname "$LOCK_PATH")',
    'XYPTDQ_PUBLISH_SOURCE=$SOURCE_Q',
    'XYPTDQ_PUBLISH_STATE=$STATE_Q',
    'XYPTDQ_PUBLISH_LOCK=$LOCK_Q',
];
foreach ($cronRequired as $needle) {
    if (strpos($cron, $needle) === false) {
        isolationFail('missing cron isolation marker: ' . $needle);
    }
}

$policyGate = strpos($cron, 'scheduled publishing is frozen by content publication policy');
$cronSourceGuard = strpos($cron, 'XYPTDQ_PUBLISH_SOURCE is required');
if ($policyGate === false || $cronSourceGuard === false || $policyGate > $cronSourceGuard) {
    isolationFail('cron installer must verify enabled publication policy before runtime-path activation');
}

if (strpos($cron, '7 * * * * root XYPTDQ_REPO_DIR=/opt/xyptdq-repo /opt/xyptdq-repo/scripts/content/run_scheduled_publish.sh') !== false) {
    isolationFail('cron installer still contains a naked runner invocation without isolated runtime bindings');
}

fwrite(STDOUT, "[publisher-source-isolation-test] PASS runner_source=isolated cron_source=isolated cron_state_lock=isolated realpath=guarded policy_pause=preserved post_publish_seo=guarded\n");

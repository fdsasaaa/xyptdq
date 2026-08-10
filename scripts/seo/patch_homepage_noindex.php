<?php
/**
 * Fail-closed patch for the legacy PC homepage robots meta.
 *
 * Default is CHECK ONLY. Use --apply only after a backup.
 * The script refuses to modify the file unless the exact legacy tag occurs once.
 *
 * Usage:
 *   php scripts/seo/patch_homepage_noindex.php --file=/path/to/template/pc/default/home/index.html
 *   php scripts/seo/patch_homepage_noindex.php --file=/path/to/template/pc/default/home/index.html --apply
 */

declare(strict_types=1);

$options = getopt('', ['file:', 'apply']);
$file = $options['file'] ?? '';
$apply = array_key_exists('apply', $options);
$legacy = '<meta name="robots" content="none">';
$replacement = '<meta name="robots" content="index,follow,max-image-preview:large">';

if ($file === '' || !is_file($file)) {
    fwrite(STDERR, "[homepage-robots] ERROR: --file must point to an existing template\n");
    exit(1);
}

$content = file_get_contents($file);
if ($content === false) {
    fwrite(STDERR, "[homepage-robots] ERROR: unable to read $file\n");
    exit(1);
}

$legacyCount = substr_count($content, $legacy);
$replacementCount = substr_count($content, $replacement);

if ($legacyCount === 0 && $replacementCount >= 1) {
    fwrite(STDOUT, "[homepage-robots] OK: template is already indexable\n");
    exit(0);
}

if ($legacyCount !== 1) {
    fwrite(STDERR, "[homepage-robots] ERROR: expected exactly 1 legacy robots tag, found $legacyCount; refusing to modify\n");
    exit(2);
}

if (!$apply) {
    fwrite(STDOUT, "[homepage-robots] CHANGE REQUIRED: exactly one legacy robots=none tag found. Re-run with --apply after backup.\n");
    exit(3);
}

$patched = str_replace($legacy, $replacement, $content, $count);
if ($count !== 1 || $patched === $content) {
    fwrite(STDERR, "[homepage-robots] ERROR: replacement invariant failed\n");
    exit(4);
}

$backup = $file . '.pre-seo-' . gmdate('Ymd_His') . '.bak';
if (!copy($file, $backup)) {
    fwrite(STDERR, "[homepage-robots] ERROR: unable to create local backup $backup\n");
    exit(5);
}

$tmp = $file . '.tmp.' . getmypid();
if (file_put_contents($tmp, $patched, LOCK_EX) === false || !rename($tmp, $file)) {
    @unlink($tmp);
    fwrite(STDERR, "[homepage-robots] ERROR: unable to atomically write patched template\n");
    exit(6);
}

fwrite(STDOUT, "[homepage-robots] OK: patched $file; backup=$backup\n");

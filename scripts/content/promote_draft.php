#!/usr/bin/env php
<?php
/** Promote one isolated website draft JSON into content/scheduled. */
declare(strict_types=1);

function promoteFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[promote-draft] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function atomicJsonWrite(string $target, array $payload): void
{
    $dir = dirname($target);
    if (!is_dir($dir) && !mkdir($dir, 0750, true) && !is_dir($dir)) {
        throw new RuntimeException('cannot create scheduled directory: ' . $dir);
    }
    $json = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    if ($json === false) {
        throw new RuntimeException('cannot encode scheduled JSON');
    }
    $tmp = $target . '.tmp.' . getmypid();
    if (file_put_contents($tmp, $json . PHP_EOL, LOCK_EX) === false) {
        throw new RuntimeException('cannot write temporary scheduled file');
    }
    if (!rename($tmp, $target)) {
        @unlink($tmp);
        throw new RuntimeException('cannot atomically replace scheduled file');
    }
}

$options = getopt('', ['input:', 'publish-at:', 'output::']);
$input = $options['input'] ?? ($argv[1] ?? '');
$publishAtRaw = $options['publish-at'] ?? '';
if ($input === '' || $publishAtRaw === '') {
    promoteFail('Usage: php promote_draft.php --input=content/drafts/key.json --publish-at=2026-08-12T09:00:00+08:00');
}

try {
    if (!is_file($input)) {
        promoteFail('draft file not found: ' . $input, 2);
    }
    $draft = json_decode((string) file_get_contents($input), true);
    if (!is_array($draft) || json_last_error() !== JSON_ERROR_NONE) {
        promoteFail('draft is invalid JSON: ' . json_last_error_msg(), 3);
    }
    if (($draft['publication_state'] ?? '') !== 'draft') {
        promoteFail('publication_state must be draft', 4);
    }
    foreach (['schema_version', 'article_key', 'title', 'content', 'catid', 'source_article_id', 'source_content_hash'] as $field) {
        if (!array_key_exists($field, $draft) || $draft[$field] === '') {
            promoteFail('required draft field missing: ' . $field, 5);
        }
    }
    if ((int) $draft['schema_version'] !== 1) {
        promoteFail('unsupported schema_version', 6);
    }
    $articleKey = (string) $draft['article_key'];
    if (preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', $articleKey) !== 1) {
        promoteFail('invalid article_key', 7);
    }
    if ((int) $draft['catid'] <= 0) {
        promoteFail('invalid catid', 8);
    }
    if (mb_strlen(trim((string) $draft['title']), 'UTF-8') < 8) {
        promoteFail('title is too short', 9);
    }
    if (mb_strlen(strip_tags((string) $draft['content']), 'UTF-8') < 180) {
        promoteFail('content is too thin', 10);
    }
    try {
        $publishAt = new DateTimeImmutable($publishAtRaw);
    } catch (Throwable $e) {
        promoteFail('invalid publish-at value', 11);
    }

    $scheduled = $draft;
    $scheduled['publish_at'] = $publishAt->format(DateTimeInterface::ATOM);
    $scheduled['publication_state'] = 'scheduled';
    $scheduled['promoted_at'] = gmdate('c');

    $repoRoot = dirname(__DIR__, 2);
    $target = $options['output'] ?? ($repoRoot . '/content/scheduled/' . $articleKey . '.json');
    if (is_file($target)) {
        $existing = json_decode((string) file_get_contents($target), true);
        if (!is_array($existing)) {
            promoteFail('existing scheduled file is invalid JSON; refusing overwrite', 12);
        }
        if (($existing['source_content_hash'] ?? '') !== $scheduled['source_content_hash']) {
            promoteFail('scheduled article_key exists with different source_content_hash', 13);
        }
        if (($existing['publish_at'] ?? '') !== $scheduled['publish_at']) {
            promoteFail('same content already scheduled for a different publish_at; explicit reschedule required', 14);
        }
        fwrite(STDOUT, json_encode([
            'status' => 'already_scheduled',
            'article_key' => $articleKey,
            'publish_at' => $scheduled['publish_at'],
            'output' => $target,
        ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
        exit(0);
    }

    atomicJsonWrite($target, $scheduled);
    fwrite(STDOUT, json_encode([
        'status' => 'scheduled',
        'article_key' => $articleKey,
        'catid' => (int) $scheduled['catid'],
        'publish_at' => $scheduled['publish_at'],
        'output' => $target,
        'publisher' => 'existing auto_publish_filequeue + verified native adapter',
    ], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);
} catch (Throwable $e) {
    promoteFail($e->getMessage(), 1);
}

<?php
/**
 * Generate sitemap.xml for laocaimi.org.
 *
 * Safe properties:
 * - Reads the existing server-side CMS database config; no credentials in Git.
 * - Emits only URLs on the configured canonical host.
 * - Writes atomically through a temporary file.
 * - Can run from cron after an article is published.
 *
 * Usage:
 *   php scripts/seo/generate_sitemap.php
 *
 * Optional environment variables:
 *   XYPTDQ_WEBROOT=/www/wwwroot/59.110.217.6
 *   XYPTDQ_DB_CONFIG=/www/wwwroot/59.110.217.6/config/database.php
 *   XYPTDQ_CANONICAL=https://www.laocaimi.org
 *   XYPTDQ_SITEMAP=/www/wwwroot/59.110.217.6/sitemap.xml
 */

declare(strict_types=1);

$webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
$dbConfigPath = getenv('XYPTDQ_DB_CONFIG') ?: $webroot . '/config/database.php';
$canonical = rtrim(getenv('XYPTDQ_CANONICAL') ?: 'https://www.laocaimi.org', '/');
$output = getenv('XYPTDQ_SITEMAP') ?: $webroot . '/sitemap.xml';

function fail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[sitemap] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

function xmlEscape(string $value): string
{
    return htmlspecialchars($value, ENT_XML1 | ENT_QUOTES, 'UTF-8');
}

function isAbsoluteUrl(string $url): bool
{
    return preg_match('~^https?://~i', $url) === 1;
}

function canonicalUrl(string $base, string $candidate): ?string
{
    $candidate = trim($candidate);
    if ($candidate === '') {
        return null;
    }

    if (isAbsoluteUrl($candidate)) {
        $baseHost = strtolower((string) parse_url($base, PHP_URL_HOST));
        $candidateHost = strtolower((string) parse_url($candidate, PHP_URL_HOST));
        if ($baseHost === '' || $candidateHost !== $baseHost) {
            return null;
        }
        $path = (string) parse_url($candidate, PHP_URL_PATH);
        $query = (string) parse_url($candidate, PHP_URL_QUERY);
        return $base . ($path ?: '/') . ($query !== '' ? '?' . $query : '');
    }

    return $base . '/' . ltrim($candidate, '/');
}

function tableExists(PDO $pdo, string $database, string $table): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = :db AND table_name = :table'
    );
    $stmt->execute([':db' => $database, ':table' => $table]);
    return (int) $stmt->fetchColumn() > 0;
}

function addUrl(array &$urls, string $loc, ?int $timestamp = null, string $priority = '0.6'): void
{
    $key = $loc;
    if (isset($urls[$key])) {
        if ($timestamp !== null && ($urls[$key]['timestamp'] ?? 0) < $timestamp) {
            $urls[$key]['timestamp'] = $timestamp;
        }
        return;
    }
    $urls[$key] = [
        'loc' => $loc,
        'timestamp' => $timestamp,
        'priority' => $priority,
    ];
}

if (!is_file($dbConfigPath)) {
    fail('Database config not found: ' . $dbConfigPath);
}

$db = [];
/** @noinspection PhpIncludeInspection */
require $dbConfigPath;

if (!isset($db['default']) || !is_array($db['default'])) {
    fail('Unexpected database.php format: $db[default] is missing.');
}

$config = $db['default'];
$host = (string) ($config['hostname'] ?? '127.0.0.1');
$user = (string) ($config['username'] ?? '');
$pass = (string) ($config['password'] ?? '');
$database = (string) ($config['database'] ?? '');
$prefix = (string) ($config['DBPrefix'] ?? 'dr_');

if ($user === '' || $database === '') {
    fail('Database username/database is missing from server configuration.');
}

try {
    $pdo = new PDO(
        'mysql:host=' . $host . ';dbname=' . $database . ';charset=utf8mb4',
        $user,
        $pass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
} catch (Throwable $e) {
    fail('Database connection failed: ' . $e->getMessage());
}

$urls = [];
addUrl($urls, $canonical . '/', time(), '1.0');

// Shared category pages.
$categoryTable = $prefix . '1_share_category';
if (tableExists($pdo, $database, $categoryTable)) {
    try {
        $sql = 'SELECT id, dirname FROM `' . str_replace('`', '', $categoryTable) . '` WHERE dirname IS NOT NULL AND dirname <> \'\'';
        foreach ($pdo->query($sql) as $row) {
            $dirname = trim((string) ($row['dirname'] ?? ''));
            if ($dirname === '') {
                continue;
            }
            $url = canonicalUrl($canonical, '/index.php?c=category&dir=' . rawurlencode($dirname));
            if ($url !== null) {
                addUrl($urls, $url, null, '0.8');
            }
        }
    } catch (Throwable $e) {
        fwrite(STDERR, '[sitemap] WARN: category query skipped: ' . $e->getMessage() . PHP_EOL);
    }
}

// Published news and platform/module content. Tables are probed at runtime so a missing module does not fail generation.
foreach (['news', 'xm'] as $module) {
    $table = $prefix . '1_' . $module;
    if (!tableExists($pdo, $database, $table)) {
        continue;
    }

    try {
        $safeTable = str_replace('`', '', $table);
        $stmt = $pdo->query('SELECT id, url, updatetime FROM `' . $safeTable . '` WHERE status = 9 ORDER BY id ASC');
        foreach ($stmt as $row) {
            $id = (int) ($row['id'] ?? 0);
            if ($id <= 0) {
                continue;
            }
            $candidate = trim((string) ($row['url'] ?? ''));
            if ($candidate === '' || isAbsoluteUrl($candidate)) {
                // Use the site's own canonical content route. External module links never belong in our sitemap.
                $candidate = '/index.php?c=show&id=' . $id;
            }
            $url = canonicalUrl($canonical, $candidate);
            if ($url === null) {
                continue;
            }
            $updated = isset($row['updatetime']) && (int) $row['updatetime'] > 0 ? (int) $row['updatetime'] : null;
            addUrl($urls, $url, $updated, $module === 'news' ? '0.7' : '0.6');
        }
    } catch (Throwable $e) {
        fwrite(STDERR, '[sitemap] WARN: ' . $module . ' query skipped: ' . $e->getMessage() . PHP_EOL);
    }
}

ksort($urls, SORT_STRING);

$xml = '<?xml version="1.0" encoding="UTF-8"?>' . PHP_EOL;
$xml .= '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . PHP_EOL;
foreach ($urls as $item) {
    $xml .= "  <url>\n";
    $xml .= '    <loc>' . xmlEscape($item['loc']) . "</loc>\n";
    if (!empty($item['timestamp'])) {
        $xml .= '    <lastmod>' . gmdate('Y-m-d\\TH:i:s\\Z', (int) $item['timestamp']) . "</lastmod>\n";
    }
    $xml .= '    <priority>' . $item['priority'] . "</priority>\n";
    $xml .= "  </url>\n";
}
$xml .= '</urlset>' . PHP_EOL;

$targetDir = dirname($output);
if (!is_dir($targetDir)) {
    fail('Sitemap target directory does not exist: ' . $targetDir);
}

$tmp = $output . '.tmp.' . getmypid();
if (file_put_contents($tmp, $xml, LOCK_EX) === false) {
    fail('Unable to write temporary sitemap: ' . $tmp);
}

if (!@rename($tmp, $output)) {
    @unlink($tmp);
    fail('Unable to atomically replace sitemap: ' . $output);
}

@chmod($output, 0644);
fwrite(STDOUT, '[sitemap] OK: ' . count($urls) . ' URLs -> ' . $output . PHP_EOL);

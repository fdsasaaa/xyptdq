<?php
/**
 * Read-only probe for Xunrui CMS news publishing tables.
 * It never writes to MariaDB. Use it to capture the exact rows/tables touched
 * by a known-good manually published article before enabling auto publishing.
 *
 * Usage:
 *   php scripts/content/publisher_probe.php --article-id=84 --output=/tmp/publisher_probe_84.json
 */

declare(strict_types=1);

$options = getopt('', ['article-id:', 'output::']);
$articleId = isset($options['article-id']) ? (int) $options['article-id'] : 0;
$output = $options['output'] ?? '';
$webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
$dbConfigPath = getenv('XYPTDQ_DB_CONFIG') ?: $webroot . '/config/database.php';

function abortProbe(string $message): void
{
    fwrite(STDERR, '[probe] ERROR: ' . $message . PHP_EOL);
    exit(1);
}

if ($articleId <= 0) {
    abortProbe('--article-id must be a positive integer');
}
if (!is_file($dbConfigPath)) {
    abortProbe('database config not found: ' . $dbConfigPath);
}

$db = [];
require $dbConfigPath;
$config = $db['default'] ?? null;
if (!is_array($config)) {
    abortProbe('unexpected database config format');
}

$database = (string) ($config['database'] ?? '');
$prefix = (string) ($config['DBPrefix'] ?? 'dr_');
$pdo = new PDO(
    'mysql:host=' . ($config['hostname'] ?? '127.0.0.1') . ';dbname=' . $database . ';charset=utf8mb4',
    (string) ($config['username'] ?? ''),
    (string) ($config['password'] ?? ''),
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
);

$like = $prefix . '1_news%';
$stmt = $pdo->prepare('SELECT table_name FROM information_schema.tables WHERE table_schema=:db AND table_name LIKE :pattern ORDER BY table_name');
$stmt->execute([':db' => $database, ':pattern' => $like]);
$tables = $stmt->fetchAll(PDO::FETCH_COLUMN);

$result = [
    'generated_at' => gmdate('c'),
    'article_id' => $articleId,
    'database' => $database,
    'table_prefix' => $prefix,
    'read_only' => true,
    'tables' => [],
];

foreach ($tables as $table) {
    $safeTable = str_replace('`', '', (string) $table);
    $columns = $pdo->query('SHOW FULL COLUMNS FROM `' . $safeTable . '`')->fetchAll();
    $columnNames = array_column($columns, 'Field');
    $entry = [
        'columns' => $columns,
        'has_id_column' => in_array('id', $columnNames, true),
        'article_row' => null,
    ];

    if ($entry['has_id_column']) {
        $rowStmt = $pdo->prepare('SELECT * FROM `' . $safeTable . '` WHERE id=:id LIMIT 1');
        $rowStmt->execute([':id' => $articleId]);
        $row = $rowStmt->fetch();
        if (is_array($row)) {
            // Keep the probe safe and compact: long content is represented by length+hash only.
            foreach ($row as $key => $value) {
                $lower = strtolower((string) $key);
                if (preg_match('/pass|password|secret|token|private|credential/', $lower)) {
                    $row[$key] = '[REDACTED]';
                } elseif ($lower === 'content' && is_string($value)) {
                    $row[$key] = [
                        'length' => strlen($value),
                        'sha256' => hash('sha256', $value),
                    ];
                }
            }
            $entry['article_row'] = $row;
        }
    }
    $result['tables'][$safeTable] = $entry;
}

$json = json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false) {
    abortProbe('json encoding failed');
}

if ($output !== '') {
    if (file_put_contents($output, $json . PHP_EOL, LOCK_EX) === false) {
        abortProbe('cannot write output: ' . $output);
    }
    fwrite(STDOUT, '[probe] OK -> ' . $output . PHP_EOL);
} else {
    fwrite(STDOUT, $json . PHP_EOL);
}

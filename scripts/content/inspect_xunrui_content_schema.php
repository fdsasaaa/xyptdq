#!/usr/bin/env php
<?php
/**
 * Read-only schema inspection for the Xunrui content tables used by laocaimi.org.
 * Outputs structural metadata only; never prints DB credentials and never writes DB rows.
 */
declare(strict_types=1);

function inspectFail(string $message, int $code = 1): void
{
    fwrite(STDERR, '[content-schema] ERROR: ' . $message . PHP_EOL);
    exit($code);
}

$webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
$dbConfigPath = getenv('XYPTDQ_DB_CONFIG') ?: $webroot . '/config/database.php';

if (!is_file($dbConfigPath)) {
    inspectFail('database config not found: ' . $dbConfigPath, 2);
}

$db = [];
require $dbConfigPath;
if (!isset($db['default']) || !is_array($db['default'])) {
    inspectFail('unexpected database.php format', 3);
}
$config = $db['default'];
$host = (string) ($config['hostname'] ?? '127.0.0.1');
$user = (string) ($config['username'] ?? '');
$pass = (string) ($config['password'] ?? '');
$database = (string) ($config['database'] ?? '');
$prefix = (string) ($config['DBPrefix'] ?? 'dr_');
if ($user === '' || $database === '') {
    inspectFail('database username/database missing', 4);
}

try {
    $pdo = new PDO(
        'mysql:host=' . $host . ';dbname=' . $database . ';charset=utf8mb4',
        $user,
        $pass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
    );
} catch (Throwable $e) {
    inspectFail('database connection failed: ' . $e->getMessage(), 5);
}

$logical = [
    'news' => $prefix . '1_news',
    'share_index' => $prefix . '1_share_index',
    'share_category' => $prefix . '1_share_category',
];

function tableColumns(PDO $pdo, string $database, string $table): array
{
    $stmt = $pdo->prepare(
        'SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA, COLUMN_KEY '
        . 'FROM information_schema.columns '
        . 'WHERE table_schema = :db AND table_name = :table ORDER BY ORDINAL_POSITION'
    );
    $stmt->execute([':db' => $database, ':table' => $table]);
    return $stmt->fetchAll();
}

function tableCount(PDO $pdo, string $database, string $table): ?int
{
    $stmt = $pdo->prepare('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=:db AND table_name=:table');
    $stmt->execute([':db' => $database, ':table' => $table]);
    if ((int) $stmt->fetchColumn() === 0) {
        return null;
    }
    $safe = str_replace('`', '', $table);
    return (int) $pdo->query('SELECT COUNT(*) FROM `' . $safe . '`')->fetchColumn();
}

$result = [
    'status' => 'read_only_schema_inspection',
    'database_name' => $database,
    'table_prefix' => $prefix,
    'tables' => [],
    'draft_import_write_enabled' => false,
];

foreach ($logical as $name => $table) {
    $columns = tableColumns($pdo, $database, $table);
    $result['tables'][$name] = [
        'table' => $table,
        'exists' => count($columns) > 0,
        'row_count' => count($columns) > 0 ? tableCount($pdo, $database, $table) : null,
        'columns' => $columns,
        'required_without_default' => array_values(array_map(
            static fn(array $c): string => (string) $c['COLUMN_NAME'],
            array_filter($columns, static function (array $c): bool {
                $extra = strtolower((string) ($c['EXTRA'] ?? ''));
                return ($c['IS_NULLABLE'] ?? 'YES') === 'NO'
                    && $c['COLUMN_DEFAULT'] === null
                    && strpos($extra, 'auto_increment') === false;
            })
        )),
    ];
}

fwrite(STDOUT, json_encode($result, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . PHP_EOL);

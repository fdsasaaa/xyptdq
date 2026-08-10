<?php
/** Read-only sanitized category probe for the Xunrui news module. */
declare(strict_types=1);

$options = getopt('', ['output::']);
$output = $options['output'] ?? '';
$webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
$dbConfigPath = getenv('XYPTDQ_DB_CONFIG') ?: $webroot . '/config/database.php';

function categoryFail(string $message): void
{
    fwrite(STDERR, '[category-probe] ERROR: ' . $message . PHP_EOL);
    exit(1);
}

if (!is_file($dbConfigPath)) {
    categoryFail('database config missing');
}
$db = [];
require $dbConfigPath;
$config = $db['default'] ?? null;
if (!is_array($config)) {
    categoryFail('unexpected database config');
}
$prefix = (string) ($config['DBPrefix'] ?? 'dr_');
if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix)) {
    categoryFail('unsafe table prefix');
}
$table = $prefix . '1_news_category';
$pdo = new PDO(
    'mysql:host=' . $config['hostname'] . ';dbname=' . $config['database'] . ';charset=utf8mb4',
    (string) $config['username'],
    (string) $config['password'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC]
);
$rows = $pdo->query(
    'SELECT id,pid,pids,name,dirname,pdirname,child,disabled,ismain,show,displayorder FROM `' . $table . '` ORDER BY displayorder ASC,id ASC'
)->fetchAll();
$result = [
    'generated_at' => gmdate('c'),
    'read_only' => true,
    'module' => 'news',
    'categories' => $rows,
];
$json = json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false) {
    categoryFail('JSON encode failed');
}
if ($output !== '') {
    if (file_put_contents($output, $json . PHP_EOL, LOCK_EX) === false) {
        categoryFail('cannot write output');
    }
    fwrite(STDOUT, '[category-probe] OK -> ' . $output . PHP_EOL);
} else {
    fwrite(STDOUT, $json . PHP_EOL);
}

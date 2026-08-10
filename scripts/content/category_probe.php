<?php
/** Read-only sanitized category probe for the Xunrui news module. */
declare(strict_types=1);

$options = getopt('', ['output::']);
$output = $options['output'] ?? '';
$webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
$dbConfigPath = getenv('XYPTDQ_DB_CONFIG') ?: $webroot . '/config/database.php';
$siteId = getenv('XYPTDQ_SITE_ID') ?: '1';
$moduleName = getenv('XYPTDQ_CMS_MODULE_NAME') ?: 'news';

function categoryFail(string $message): void
{
    fwrite(STDERR, '[category-probe] ERROR: ' . $message . PHP_EOL);
    exit(1);
}

function categoryTableExists(PDO $pdo, string $database, string $table): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=:db AND table_name=:table'
    );
    $stmt->execute([':db' => $database, ':table' => $table]);
    return (int) $stmt->fetchColumn() > 0;
}

function categoryColumns(PDO $pdo, string $database, string $table): array
{
    $stmt = $pdo->prepare(
        'SELECT column_name FROM information_schema.columns WHERE table_schema=:db AND table_name=:table ORDER BY ordinal_position'
    );
    $stmt->execute([':db' => $database, ':table' => $table]);
    return array_map('strval', $stmt->fetchAll(PDO::FETCH_COLUMN));
}

function categoryQuotedSelect(array $columns): string
{
    return implode(',', array_map(static function (string $column): string {
        return '`' . str_replace('`', '', $column) . '`';
    }, $columns));
}

if (!is_file($dbConfigPath)) {
    categoryFail('database config missing');
}
if (!preg_match('/^[0-9]+$/', (string) $siteId)) {
    categoryFail('unsafe site id');
}
if (!preg_match('/^[A-Za-z0-9_]+$/', (string) $moduleName)) {
    categoryFail('unsafe module name');
}

$db = [];
require $dbConfigPath;
$config = $db['default'] ?? null;
if (!is_array($config)) {
    categoryFail('unexpected database config');
}
$prefix = (string) ($config['DBPrefix'] ?? 'dr_');
$database = (string) ($config['database'] ?? '');
if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix) || !preg_match('/^[A-Za-z0-9_]+$/', $database)) {
    categoryFail('unsafe database metadata');
}

$pdo = new PDO(
    'mysql:host=' . $config['hostname'] . ';dbname=' . $database . ';charset=utf8mb4',
    (string) $config['username'],
    (string) $config['password'],
    [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        PDO::ATTR_EMULATE_PREPARES => false,
    ]
);

$dedicated = $prefix . $siteId . '_' . $moduleName . '_category';
$shared = $prefix . $siteId . '_share_category';
$sources = [];
$effective = [];

foreach ([
    ['table' => $dedicated, 'model' => 'dedicated'],
    ['table' => $shared, 'model' => 'shared'],
] as $candidate) {
    $table = $candidate['table'];
    $model = $candidate['model'];
    if (!categoryTableExists($pdo, $database, $table)) {
        $sources[] = ['table' => $table, 'model' => $model, 'exists' => false, 'count' => 0];
        continue;
    }

    $available = categoryColumns($pdo, $database, $table);
    if (!in_array('id', $available, true)) {
        $sources[] = ['table' => $table, 'model' => $model, 'exists' => true, 'count' => 0, 'usable' => false];
        continue;
    }

    $wanted = ['id','pid','name','dirname','disabled','show','displayorder','mid','module','module_name'];
    $selected = array_values(array_filter($wanted, static function (string $column) use ($available): bool {
        return in_array($column, $available, true);
    }));

    $sql = 'SELECT ' . categoryQuotedSelect($selected) . ' FROM `' . $table . '`';
    $params = [];
    $moduleColumn = null;
    if ($model === 'shared') {
        foreach (['mid', 'module', 'module_name'] as $marker) {
            if (in_array($marker, $available, true)) {
                $moduleColumn = $marker;
                break;
            }
        }
        if ($moduleColumn !== null) {
            $sql .= ' WHERE `' . $moduleColumn . '`=:module_name';
            $params[':module_name'] = $moduleName;
        }
    }
    if (in_array('displayorder', $available, true)) {
        $sql .= ' ORDER BY `displayorder` ASC,`id` ASC';
    } else {
        $sql .= ' ORDER BY `id` ASC';
    }

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();
    $sources[] = [
        'table' => $table,
        'model' => $model,
        'exists' => true,
        'usable' => true,
        'module_filter_column' => $moduleColumn,
        'count' => count($rows),
    ];

    foreach ($rows as $row) {
        $id = (int) ($row['id'] ?? 0);
        if ($id <= 0) {
            continue;
        }
        $row['_source_table'] = $table;
        $row['_source_model'] = $model;
        // Prefer a dedicated module row when both layouts expose the same ID.
        if (!isset($effective[$id]) || $model === 'dedicated') {
            $effective[$id] = $row;
        }
    }
}

ksort($effective, SORT_NUMERIC);
$result = [
    'generated_at' => gmdate('c'),
    'read_only' => true,
    'site_id' => (int) $siteId,
    'module' => $moduleName,
    'sources' => $sources,
    'categories' => array_values($effective),
];

$json = json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
if ($json === false) {
    categoryFail('JSON encode failed');
}
if ($output !== '') {
    if (file_put_contents($output, $json . PHP_EOL, LOCK_EX) === false) {
        categoryFail('cannot write output');
    }
    fwrite(STDOUT, '[category-probe] OK categories=' . count($effective) . ' -> ' . $output . PHP_EOL);
} else {
    fwrite(STDOUT, $json . PHP_EOL);
}

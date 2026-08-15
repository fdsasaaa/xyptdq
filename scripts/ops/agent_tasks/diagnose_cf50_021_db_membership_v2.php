<?php
/** Read-only CMS94 Sitemap membership diagnostic. */
declare(strict_types=1);

$resultFile = getenv('XYPTDQ_AGENT_RESULT_FILE') ?: '';
$webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
if ($resultFile === '') {
    fwrite(STDERR, "missing result file\n");
    exit(2);
}

$payload = [
    'task' => 'diagnose_cf50_021_db_membership_v2',
    'status' => 'PASS',
    'read_only' => true,
    'cms_id' => 94,
    'cms_write_attempted' => false,
    'production_sitemap_mutated' => false,
    'cron_mutated' => false,
    'queue_consumed' => false,
];

$write = static function (array $data) use ($resultFile): void {
    file_put_contents(
        $resultFile,
        json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n"
    );
};

try {
    $db = [];
    $configPath = $webroot . '/config/database.php';
    if (!is_file($configPath)) {
        throw new RuntimeException('database config missing');
    }
    require $configPath;
    $config = $db['default'] ?? null;
    if (!is_array($config)) {
        throw new RuntimeException('database config invalid');
    }
    $prefix = (string) ($config['DBPrefix'] ?? 'dr_');
    if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix)) {
        throw new RuntimeException('database prefix unsafe');
    }
    $database = (string) ($config['database'] ?? '');
    $pdo = new PDO(
        'mysql:host=' . (string) $config['hostname'] . ';dbname=' . $database . ';charset=utf8mb4',
        (string) $config['username'],
        (string) $config['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );

    $tableExists = static function (PDO $pdo, string $database, string $table): bool {
        $stmt = $pdo->prepare('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=:db AND table_name=:table');
        $stmt->execute([':db' => $database, ':table' => $table]);
        return (int) $stmt->fetchColumn() > 0;
    };
    $one = static function (PDO $pdo, string $sql, array $params = []): array {
        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch();
        return is_array($row) ? $row : [];
    };

    $news = $prefix . '1_news';
    $share = $prefix . '1_share_index';
    $registry = $prefix . 'xyptdq_publish_registry';
    $tables = [
        'news' => $tableExists($pdo, $database, $news),
        'share_index' => $tableExists($pdo, $database, $share),
        'registry' => $tableExists($pdo, $database, $registry),
    ];
    $payload['db_prefix'] = $prefix;
    $payload['tables'] = $tables;

    $newsRow = $tables['news']
        ? $one($pdo, 'SELECT `id`,`catid`,`title`,`status`,`url`,`tableid`,`updatetime` FROM `' . $news . '` WHERE `id`=94 LIMIT 1')
        : [];
    $shareRow = $tables['share_index']
        ? $one($pdo, 'SELECT `id`,`mid` FROM `' . $share . '` WHERE `id`=94 LIMIT 1')
        : [];
    $registryRow = $tables['registry']
        ? $one($pdo, 'SELECT `article_key`,`cms_id`,`content_hash`,`source_file`,`published_at` FROM `' . $registry . '` WHERE `cms_id`=94 LIMIT 1')
        : [];
    $joinRow = ($tables['news'] && $tables['share_index'])
        ? $one(
            $pdo,
            'SELECT m.`id`,m.`url`,m.`status`,m.`updatetime`,s.`mid` FROM `' . $news . '` m '
            . 'INNER JOIN `' . $share . '` s ON s.`id`=m.`id` AND s.`mid`=:mid '
            . 'WHERE m.`status`=9 AND m.`id`=94 LIMIT 1',
            [':mid' => 'news']
        )
        : [];

    $payload['news_94'] = $newsRow;
    $payload['share_94'] = $shareRow;
    $payload['registry_94'] = $registryRow;
    $payload['generator_join_94'] = $joinRow;

    $wouldUseManagedCanonical = !empty($joinRow) && !empty($registryRow) && (int) ($registryRow['cms_id'] ?? 0) === 94;
    $payload['would_use_managed_canonical'] = $wouldUseManagedCanonical;
    $payload['generator_candidate_url'] = !empty($joinRow)
        ? ($wouldUseManagedCanonical
            ? '/index.php?c=show&id=94'
            : ((trim((string) ($joinRow['url'] ?? '')) !== '' && !preg_match('~^https?://~i', (string) $joinRow['url']))
                ? (string) $joinRow['url']
                : '/index.php?c=show&id=94'))
        : null;

    if (empty($newsRow)) {
        $cause = 'cms_news_row_missing';
    } elseif ((int) ($newsRow['status'] ?? 0) !== 9) {
        $cause = 'cms_news_status_not_published';
    } elseif (empty($shareRow)) {
        $cause = 'share_index_row_missing';
    } elseif ((string) ($shareRow['mid'] ?? '') !== 'news') {
        $cause = 'share_index_mid_mismatch';
    } elseif (empty($joinRow)) {
        $cause = 'generator_inner_join_excludes_94';
    } elseif (empty($registryRow)) {
        $cause = 'publisher_registry_row_missing';
    } else {
        $cause = 'cms94_is_generator_eligible_with_publisher_registry';
    }
    $payload['root_cause_candidate'] = $cause;
    $write($payload);
    echo "CF50_021_DB_MEMBERSHIP_V2=PASS\n";
    exit(0);
} catch (Throwable $e) {
    $payload['status'] = 'FAIL';
    $payload['phase'] = 'exception';
    $payload['error'] = mb_substr($e->getMessage(), 0, 1000, 'UTF-8');
    $write($payload);
    fwrite(STDERR, "CF50_021_DB_MEMBERSHIP_V2=FAIL\n");
    exit(20);
}

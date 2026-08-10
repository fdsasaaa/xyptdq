<?php
/**
 * Xunrui-native publisher adapter for xyptdq.
 *
 * Content creation is delegated to Xunrui's own module lifecycle
 * (`_module_init` + `content_model->save_content`) through a CLI-only API shim.
 * Direct SQL is used only for read-only verification and the xyptdq durable
 * article-key registry; it is never used to manufacture CMS content rows.
 */
declare(strict_types=1);

function xyptdq_native_fail(string $message): void
{
    throw new RuntimeException($message);
}

function xyptdq_native_identifier(string $value, string $label): string
{
    if (!preg_match('/^[A-Za-z0-9_]+$/', $value)) {
        xyptdq_native_fail('unsafe SQL identifier for ' . $label);
    }
    return $value;
}

function xyptdq_native_load_db_config(): array
{
    $webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
    $path = getenv('XYPTDQ_DB_CONFIG') ?: $webroot . '/config/database.php';
    if (!is_file($path)) {
        xyptdq_native_fail('database config not found');
    }
    $db = [];
    require $path;
    $config = $db['default'] ?? null;
    if (!is_array($config)) {
        xyptdq_native_fail('unexpected database config format');
    }
    foreach (['hostname', 'username', 'password', 'database'] as $key) {
        if (!array_key_exists($key, $config)) {
            xyptdq_native_fail('database config field missing: ' . $key);
        }
    }
    return $config;
}

function xyptdq_native_open_pdo(array $config): PDO
{
    return new PDO(
        'mysql:host=' . (string) $config['hostname'] . ';dbname=' . (string) $config['database'] . ';charset=utf8mb4',
        (string) $config['username'],
        (string) $config['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]
    );
}

function xyptdq_native_table_exists(PDO $pdo, string $database, string $table): bool
{
    $stmt = $pdo->prepare('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=:db AND table_name=:table');
    $stmt->execute([':db' => $database, ':table' => $table]);
    return (int) $stmt->fetchColumn() > 0;
}

function xyptdq_native_columns(PDO $pdo, string $database, string $table): array
{
    $stmt = $pdo->prepare('SELECT column_name FROM information_schema.columns WHERE table_schema=:db AND table_name=:table ORDER BY ordinal_position');
    $stmt->execute([':db' => $database, ':table' => $table]);
    return array_map('strval', $stmt->fetchAll(PDO::FETCH_COLUMN));
}

function xyptdq_native_require_columns(PDO $pdo, string $database, string $table, array $required): void
{
    if (!xyptdq_native_table_exists($pdo, $database, $table)) {
        xyptdq_native_fail('required CMS table missing: ' . $table);
    }
    $have = xyptdq_native_columns($pdo, $database, $table);
    foreach ($required as $column) {
        if (!in_array($column, $have, true)) {
            xyptdq_native_fail('required column missing: ' . $table . '.' . $column);
        }
    }
}

function xyptdq_native_article_hash(array $article): string
{
    if (!empty($article['_content_hash']) && preg_match('/^[a-f0-9]{64}$/', (string) $article['_content_hash'])) {
        return (string) $article['_content_hash'];
    }
    $copy = $article;
    foreach (['_source_file', '_publish_at_iso', '_publish_at_ts', '_content_hash'] as $key) {
        unset($copy[$key]);
    }
    $encoded = json_encode($copy, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($encoded === false) {
        xyptdq_native_fail('cannot hash article JSON');
    }
    return hash('sha256', $encoded);
}

function xyptdq_native_ensure_registry(PDO $pdo, string $registry): void
{
    $pdo->exec(
        'CREATE TABLE IF NOT EXISTS `' . $registry . '` ('
        . '`article_key` varchar(80) NOT NULL,'
        . '`cms_id` int(10) unsigned NOT NULL,'
        . '`content_hash` char(64) NOT NULL,'
        . '`source_file` varchar(255) DEFAULT NULL,'
        . '`published_at` int(10) unsigned NOT NULL,'
        . 'PRIMARY KEY (`article_key`),'
        . 'UNIQUE KEY `uniq_cms_id` (`cms_id`)'
        . ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );
}

/** @return array{source:string,row:array} */
function xyptdq_native_resolve_category(
    PDO $pdo,
    string $database,
    string $prefix,
    string $module,
    string $newsTable,
    int $catid
): array {
    if (!preg_match('/^([0-9]+)_([A-Za-z0-9_]+)$/', $module, $m)) {
        xyptdq_native_fail('unexpected CMS module identifier');
    }
    $siteId = $m[1];
    $moduleName = $m[2];

    $dedicated = xyptdq_native_identifier($prefix . $module . '_category', 'dedicated category table');
    if (xyptdq_native_table_exists($pdo, $database, $dedicated)) {
        $columns = xyptdq_native_columns($pdo, $database, $dedicated);
        if (in_array('id', $columns, true)) {
            $select = ['id'];
            foreach (['disabled', 'show', 'name', 'dirname'] as $col) {
                if (in_array($col, $columns, true)) {
                    $select[] = $col;
                }
            }
            $quoted = array_map(static function (string $col): string { return '`' . $col . '`'; }, $select);
            $stmt = $pdo->prepare('SELECT ' . implode(',', $quoted) . ' FROM `' . $dedicated . '` WHERE `id`=:id LIMIT 1');
            $stmt->execute([':id' => $catid]);
            $row = $stmt->fetch();
            if (is_array($row)) {
                if (isset($row['disabled']) && (int) $row['disabled'] !== 0) {
                    xyptdq_native_fail('target category is disabled');
                }
                if (isset($row['show']) && (int) $row['show'] === 0) {
                    xyptdq_native_fail('target category is hidden');
                }
                return ['source' => $dedicated, 'row' => $row];
            }
        }
    }

    $shared = xyptdq_native_identifier($prefix . $siteId . '_share_category', 'shared category table');
    if (xyptdq_native_table_exists($pdo, $database, $shared)) {
        $columns = xyptdq_native_columns($pdo, $database, $shared);
        if (in_array('id', $columns, true)) {
            $select = ['id'];
            foreach (['disabled', 'show', 'name', 'dirname', 'mid', 'module', 'module_name'] as $col) {
                if (in_array($col, $columns, true)) {
                    $select[] = $col;
                }
            }
            $moduleColumn = null;
            foreach (['mid', 'module', 'module_name'] as $candidate) {
                if (in_array($candidate, $columns, true)) {
                    $moduleColumn = $candidate;
                    break;
                }
            }
            $where = '`id`=:id';
            $params = [':id' => $catid];
            if ($moduleColumn !== null) {
                $where .= ' AND `' . $moduleColumn . '`=:module_name';
                $params[':module_name'] = $moduleName;
            }
            $quoted = array_map(static function (string $col): string { return '`' . $col . '`'; }, $select);
            $stmt = $pdo->prepare('SELECT ' . implode(',', $quoted) . ' FROM `' . $shared . '` WHERE ' . $where . ' LIMIT 1');
            $stmt->execute($params);
            $row = $stmt->fetch();
            if (is_array($row)) {
                if (isset($row['disabled']) && (int) $row['disabled'] !== 0) {
                    xyptdq_native_fail('target category is disabled');
                }
                if (isset($row['show']) && (int) $row['show'] === 0) {
                    xyptdq_native_fail('target category is hidden');
                }
                return ['source' => $shared, 'row' => $row];
            }
        }
    }

    $stmt = $pdo->prepare('SELECT `id`,`catid`,`status` FROM `' . $newsTable . '` WHERE `catid`=:catid AND `status`=9 ORDER BY `id` DESC LIMIT 1');
    $stmt->execute([':catid' => $catid]);
    $row = $stmt->fetch();
    if (is_array($row)) {
        return ['source' => 'existing_published_content', 'row' => $row];
    }
    xyptdq_native_fail('target category does not exist');
}

/** @return array{site_id:string,module_name:string,module:string,news:string,registry:string,share_index:string} */
function xyptdq_native_layout(array $config): array
{
    $prefix = (string) ($config['DBPrefix'] ?? 'dr_');
    if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix)) {
        xyptdq_native_fail('unsafe database table prefix');
    }
    $module = xyptdq_native_identifier(getenv('XYPTDQ_CMS_MODULE') ?: '1_news', 'module');
    if (!preg_match('/^([0-9]+)_([A-Za-z0-9_]+)$/', $module, $m)) {
        xyptdq_native_fail('unexpected CMS module identifier');
    }
    return [
        'site_id' => $m[1],
        'module_name' => $m[2],
        'module' => $module,
        'news' => xyptdq_native_identifier($prefix . $module, 'news table'),
        'registry' => xyptdq_native_identifier($prefix . 'xyptdq_publish_registry', 'registry table'),
        'share_index' => xyptdq_native_identifier($prefix . $m[1] . '_share_index', 'shared index table'),
    ];
}

function xyptdq_native_assert_allocator_safe(PDO $pdo, string $database, string $prefix, array $layout): void
{
    $share = $layout['share_index'];
    xyptdq_native_require_columns($pdo, $database, $share, ['id', 'mid']);
    $stmt = $pdo->prepare('SELECT AUTO_INCREMENT FROM information_schema.tables WHERE table_schema=:db AND table_name=:table LIMIT 1');
    $stmt->execute([':db' => $database, ':table' => $share]);
    $next = (int) $stmt->fetchColumn();
    if ($next <= 0) {
        $next = (int) $pdo->query('SELECT COALESCE(MAX(`id`),0)+1 FROM `' . $share . '`')->fetchColumn();
    }

    $all = $pdo->prepare('SELECT table_name FROM information_schema.tables WHERE table_schema=:db ORDER BY table_name');
    $all->execute([':db' => $database]);
    $maxModuleId = 0;
    $root = $prefix . $layout['site_id'] . '_';
    $pattern = '/^' . preg_quote($root, '/') . '[A-Za-z0-9_]+_index$/';
    foreach ($all->fetchAll(PDO::FETCH_COLUMN) as $table) {
        $table = (string) $table;
        if ($table === $share || !preg_match($pattern, $table)) {
            continue;
        }
        $safe = xyptdq_native_identifier($table, 'module index table');
        $max = (int) $pdo->query('SELECT COALESCE(MAX(`id`),0) FROM `' . $safe . '`')->fetchColumn();
        if ($max > $maxModuleId) {
            $maxModuleId = $max;
        }
    }
    if ($next <= $maxModuleId) {
        xyptdq_native_fail('shared content id allocator is behind module indexes');
    }
}

/** @return array{main:array,data:array,share:array} */
function xyptdq_native_identity(PDO $pdo, string $database, string $prefix, array $layout, int $cmsId): array
{
    $news = $layout['news'];
    $stmt = $pdo->prepare('SELECT `id`,`catid`,`title`,`status`,`url`,`tableid` FROM `' . $news . '` WHERE `id`=:id LIMIT 1');
    $stmt->execute([':id' => $cmsId]);
    $main = $stmt->fetch();
    if (!is_array($main)) {
        return ['main' => [], 'data' => [], 'share' => []];
    }
    $tableId = (int) ($main['tableid'] ?? 0);
    if ($tableId < 0 || $tableId > 9999) {
        xyptdq_native_fail('unsafe CMS data partition');
    }
    $dataTable = xyptdq_native_identifier($prefix . $layout['module'] . '_data_' . $tableId, 'data table');
    xyptdq_native_require_columns($pdo, $database, $dataTable, ['id', 'catid', 'content']);
    $stmt = $pdo->prepare('SELECT `id`,`catid`,`content` FROM `' . $dataTable . '` WHERE `id`=:id LIMIT 1');
    $stmt->execute([':id' => $cmsId]);
    $data = $stmt->fetch();
    $stmt = $pdo->prepare('SELECT `id`,`mid` FROM `' . $layout['share_index'] . '` WHERE `id`=:id LIMIT 1');
    $stmt->execute([':id' => $cmsId]);
    $share = $stmt->fetch();
    return [
        'main' => is_array($main) ? $main : [],
        'data' => is_array($data) ? $data : [],
        'share' => is_array($share) ? $share : [],
    ];
}

function xyptdq_native_identity_matches(array $identity, array $article, string $moduleName): bool
{
    $main = $identity['main'] ?? [];
    $data = $identity['data'] ?? [];
    $share = $identity['share'] ?? [];
    return is_array($main)
        && is_array($data)
        && is_array($share)
        && (int) ($main['id'] ?? 0) > 0
        && (int) ($main['catid'] ?? 0) === (int) $article['catid']
        && (int) ($main['status'] ?? 0) === 9
        && trim((string) ($main['title'] ?? '')) === trim((string) $article['title'])
        && (int) ($data['id'] ?? 0) === (int) ($main['id'] ?? 0)
        && (int) ($data['catid'] ?? 0) === (int) $article['catid']
        && (string) ($data['content'] ?? '') === (string) $article['content']
        && (int) ($share['id'] ?? 0) === (int) ($main['id'] ?? 0)
        && (string) ($share['mid'] ?? '') === $moduleName;
}

function xyptdq_native_register(PDO $pdo, string $registry, string $articleKey, int $cmsId, string $contentHash, string $sourceFile): void
{
    $pdo->beginTransaction();
    try {
        $stmt = $pdo->prepare('SELECT `cms_id`,`content_hash` FROM `' . $registry . '` WHERE `article_key`=:article_key FOR UPDATE');
        $stmt->execute([':article_key' => $articleKey]);
        $row = $stmt->fetch();
        if (is_array($row)) {
            if ((int) $row['cms_id'] !== $cmsId || !hash_equals((string) $row['content_hash'], $contentHash)) {
                throw new RuntimeException('publisher registry conflict');
            }
        } else {
            $stmt = $pdo->prepare(
                'INSERT INTO `' . $registry . '` (`article_key`,`cms_id`,`content_hash`,`source_file`,`published_at`) '
                . 'VALUES (:article_key,:cms_id,:content_hash,:source_file,:published_at)'
            );
            $stmt->execute([
                ':article_key' => $articleKey,
                ':cms_id' => $cmsId,
                ':content_hash' => $contentHash,
                ':source_file' => $sourceFile,
                ':published_at' => time(),
            ]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

/** @return array{ok:bool,cms_id?:int,error?:string} */
function xyptdq_native_run_cms(array $article): array
{
    $repoRoot = dirname(__DIR__, 2);
    $webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
    $entrySrc = $repoRoot . '/scripts/content/native_api/xyptdq.php';
    $handlerSrc = $repoRoot . '/scripts/content/native_api/Xyptdq.php';
    $entryDst = $webroot . '/api/xyptdq.php';
    $handlerDst = $webroot . '/dayrui/My/Api/Xyptdq.php';
    foreach ([$entrySrc, $handlerSrc] as $file) {
        if (!is_file($file) || filesize($file) <= 0) {
            xyptdq_native_fail('native CMS bridge source missing');
        }
    }

    $inputDir = getenv('XYPTDQ_NATIVE_INPUT_DIR') ?: '/var/lib/xyptdq-publisher/native-input';
    if (!is_dir($inputDir) && !mkdir($inputDir, 0700, true) && !is_dir($inputDir)) {
        xyptdq_native_fail('cannot create native CMS input directory');
    }
    @chmod($inputDir, 0700);
    $input = tempnam($inputDir, 'article.');
    if ($input === false) {
        xyptdq_native_fail('cannot create native CMS input file');
    }
    $json = json_encode($article, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($json === false || file_put_contents($input, $json . PHP_EOL, LOCK_EX) === false) {
        @unlink($input);
        xyptdq_native_fail('cannot write native CMS input file');
    }
    @chmod($input, 0600);

    $createdEntry = false;
    $createdHandler = false;
    $oldArticleEnv = getenv('XYPTDQ_NATIVE_ARTICLE_FILE');
    $oldRootEnv = getenv('XYPTDQ_REPO_CONTENT_ROOT');
    try {
        foreach ([dirname($entryDst), dirname($handlerDst)] as $dir) {
            if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
                xyptdq_native_fail('cannot create native CMS bridge directory');
            }
        }
        if (is_file($entryDst)) {
            if (!hash_equals((string) hash_file('sha256', $entrySrc), (string) hash_file('sha256', $entryDst))) {
                xyptdq_native_fail('unexpected native CMS entry already exists');
            }
        } else {
            if (!copy($entrySrc, $entryDst)) {
                xyptdq_native_fail('cannot install native CMS entry');
            }
            @chmod($entryDst, 0644);
            $createdEntry = true;
        }
        if (is_file($handlerDst)) {
            if (!hash_equals((string) hash_file('sha256', $handlerSrc), (string) hash_file('sha256', $handlerDst))) {
                xyptdq_native_fail('unexpected native CMS handler already exists');
            }
        } else {
            if (!copy($handlerSrc, $handlerDst)) {
                xyptdq_native_fail('cannot install native CMS handler');
            }
            @chmod($handlerDst, 0644);
            $createdHandler = true;
        }

        putenv('XYPTDQ_NATIVE_ARTICLE_FILE=' . $input);
        putenv('XYPTDQ_REPO_CONTENT_ROOT=' . $inputDir);
        $stdout = '';
        $stderr = '';
        $command = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg($entryDst);
        $proc = proc_open($command, [
            0 => ['pipe', 'r'],
            1 => ['pipe', 'w'],
            2 => ['pipe', 'w'],
        ], $pipes);
        if (!is_resource($proc)) {
            xyptdq_native_fail('cannot start native CMS process');
        }
        fclose($pipes[0]);
        $stdout = (string) stream_get_contents($pipes[1]);
        $stderr = (string) stream_get_contents($pipes[2]);
        fclose($pipes[1]);
        fclose($pipes[2]);
        $rc = proc_close($proc);
        if ($rc !== 0) {
            xyptdq_native_fail('native CMS process failed');
        }
        $encoded = '';
        foreach (preg_split('/\R/', $stdout) ?: [] as $line) {
            if (strpos($line, 'XYPTDQ_NATIVE_RESULT=') === 0) {
                $encoded = substr($line, strlen('XYPTDQ_NATIVE_RESULT='));
            }
        }
        if ($encoded === '') {
            xyptdq_native_fail('native CMS result missing');
        }
        $decoded = base64_decode($encoded, true);
        $result = $decoded === false ? null : json_decode($decoded, true);
        if (!is_array($result) || empty($result['ok']) || (int) ($result['cms_id'] ?? 0) <= 0) {
            $reason = is_array($result) ? (string) ($result['error'] ?? 'unknown') : 'invalid';
            xyptdq_native_fail('native CMS save rejected: ' . preg_replace('/[^A-Z0-9_-]/', '', strtoupper($reason)));
        }
        return ['ok' => true, 'cms_id' => (int) $result['cms_id']];
    } finally {
        if ($oldArticleEnv === false) {
            putenv('XYPTDQ_NATIVE_ARTICLE_FILE');
        } else {
            putenv('XYPTDQ_NATIVE_ARTICLE_FILE=' . $oldArticleEnv);
        }
        if ($oldRootEnv === false) {
            putenv('XYPTDQ_REPO_CONTENT_ROOT');
        } else {
            putenv('XYPTDQ_REPO_CONTENT_ROOT=' . $oldRootEnv);
        }
        @unlink($input);
        if ($createdHandler) {
            @unlink($handlerDst);
        }
        if ($createdEntry) {
            @unlink($entryDst);
        }
    }
}

/** @return array{cms_id:int,url:string,idempotent:bool} */
function xyptdq_publish_article(array $article): array
{
    foreach (['article_key', 'title', 'content', 'catid'] as $field) {
        if (!array_key_exists($field, $article) || $article[$field] === '') {
            xyptdq_native_fail('article field missing: ' . $field);
        }
    }
    $articleKey = (string) $article['article_key'];
    if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', $articleKey)) {
        xyptdq_native_fail('invalid article_key');
    }
    $title = trim((string) $article['title']);
    if (mb_strlen($title, 'UTF-8') < 8 || mb_strlen($title, 'UTF-8') > 255) {
        xyptdq_native_fail('title length is outside CMS safety bounds');
    }
    if (mb_strlen(strip_tags((string) $article['content']), 'UTF-8') < 180) {
        xyptdq_native_fail('article content is too thin');
    }
    $catid = (int) $article['catid'];
    if ($catid <= 0) {
        xyptdq_native_fail('invalid catid');
    }

    $config = xyptdq_native_load_db_config();
    $database = xyptdq_native_identifier((string) $config['database'], 'database');
    $prefix = (string) ($config['DBPrefix'] ?? 'dr_');
    if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix)) {
        xyptdq_native_fail('unsafe database table prefix');
    }
    $layout = xyptdq_native_layout($config);
    $pdo = xyptdq_native_open_pdo($config);
    xyptdq_native_require_columns($pdo, $database, $layout['news'], ['id', 'catid', 'title', 'status', 'url', 'tableid']);
    xyptdq_native_ensure_registry($pdo, $layout['registry']);
    xyptdq_native_resolve_category($pdo, $database, $prefix, $layout['module'], $layout['news'], $catid);

    $contentHash = xyptdq_native_article_hash($article);
    $sourceFile = mb_substr((string) ($article['_source_file'] ?? ''), 0, 255, 'UTF-8');
    $stmt = $pdo->prepare('SELECT `cms_id`,`content_hash` FROM `' . $layout['registry'] . '` WHERE `article_key`=:article_key LIMIT 1');
    $stmt->execute([':article_key' => $articleKey]);
    $registered = $stmt->fetch();
    if (is_array($registered)) {
        if (!hash_equals((string) $registered['content_hash'], $contentHash)) {
            xyptdq_native_fail('article_key already published with different content');
        }
        $cmsId = (int) $registered['cms_id'];
        $identity = xyptdq_native_identity($pdo, $database, $prefix, $layout, $cmsId);
        if (!xyptdq_native_identity_matches($identity, $article, $layout['module_name'])) {
            xyptdq_native_fail('registered CMS article no longer matches immutable source');
        }
        return [
            'cms_id' => $cmsId,
            'url' => '/index.php?c=show&id=' . $cmsId,
            'idempotent' => true,
        ];
    }

    // Crash recovery: native CMS save may have committed immediately before a
    // process died and before the durable registry row was written.
    $stmt = $pdo->prepare('SELECT `id` FROM `' . $layout['news'] . '` WHERE `title`=:title ORDER BY `id`');
    $stmt->execute([':title' => $title]);
    $titleIds = array_map('intval', $stmt->fetchAll(PDO::FETCH_COLUMN));
    if (count($titleIds) > 1) {
        xyptdq_native_fail('multiple CMS rows already use the immutable title');
    }
    if (count($titleIds) === 1) {
        $cmsId = $titleIds[0];
        $identity = xyptdq_native_identity($pdo, $database, $prefix, $layout, $cmsId);
        if (!xyptdq_native_identity_matches($identity, $article, $layout['module_name'])) {
            xyptdq_native_fail('existing CMS title conflicts with immutable source');
        }
        xyptdq_native_register($pdo, $layout['registry'], $articleKey, $cmsId, $contentHash, $sourceFile);
        return [
            'cms_id' => $cmsId,
            'url' => '/index.php?c=show&id=' . $cmsId,
            'idempotent' => true,
        ];
    }

    xyptdq_native_assert_allocator_safe($pdo, $database, $prefix, $layout);
    $native = xyptdq_native_run_cms($article);
    $cmsId = (int) ($native['cms_id'] ?? 0);
    if ($cmsId <= 0) {
        xyptdq_native_fail('native CMS returned invalid id');
    }

    // Re-open after the child CMS process commits so verification sees the
    // authoritative rows and the shared routing index.
    $pdo = xyptdq_native_open_pdo($config);
    $identity = xyptdq_native_identity($pdo, $database, $prefix, $layout, $cmsId);
    if (!xyptdq_native_identity_matches($identity, $article, $layout['module_name'])) {
        xyptdq_native_fail('native CMS article failed post-save identity verification');
    }
    xyptdq_native_register($pdo, $layout['registry'], $articleKey, $cmsId, $contentHash, $sourceFile);

    return [
        'cms_id' => $cmsId,
        'url' => '/index.php?c=show&id=' . $cmsId,
        'idempotent' => false,
    ];
}

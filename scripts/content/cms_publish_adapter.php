<?php
/**
 * Transactional Xunrui CMS publisher adapter for xyptdq.
 *
 * Evidence basis:
 * - docs/probes/publisher_probe_full_47.json (production, read-only)
 * - immediate published article 47 has rows in:
 *   dr_1_news, dr_1_news_data_0, dr_1_news_hits, dr_1_news_index
 * - dr_1_news_time and dr_1_news_search exist but have no row for article 47.
 *
 * Category model:
 * Xunrui installations may keep module categories in either a dedicated
 * <site>_<module>_category table or the site-wide <site>_share_category table.
 * The production site currently exposes SEO category 7 through the shared
 * category model, so validation resolves both layouts safely.
 *
 * Durable idempotency:
 * A dedicated dr_xyptdq_publish_registry table stores article_key -> cms_id in
 * the same database. Re-running an already committed article returns the same
 * cms_id instead of inserting a duplicate.
 */

declare(strict_types=1);

function xyptdq_adapter_fail(string $message): void
{
    throw new RuntimeException($message);
}

function xyptdq_identifier(string $value, string $label): string
{
    if (!preg_match('/^[A-Za-z0-9_]+$/', $value)) {
        xyptdq_adapter_fail('unsafe SQL identifier for ' . $label);
    }
    return $value;
}

function xyptdq_table_exists(PDO $pdo, string $database, string $table): bool
{
    $stmt = $pdo->prepare(
        'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema=:db AND table_name=:table'
    );
    $stmt->execute([':db' => $database, ':table' => $table]);
    return (int) $stmt->fetchColumn() > 0;
}

function xyptdq_columns(PDO $pdo, string $database, string $table): array
{
    $stmt = $pdo->prepare(
        'SELECT column_name FROM information_schema.columns WHERE table_schema=:db AND table_name=:table ORDER BY ordinal_position'
    );
    $stmt->execute([':db' => $database, ':table' => $table]);
    return array_map('strval', $stmt->fetchAll(PDO::FETCH_COLUMN));
}

function xyptdq_require_columns(PDO $pdo, string $database, string $table, array $required): void
{
    if (!xyptdq_table_exists($pdo, $database, $table)) {
        xyptdq_adapter_fail('required CMS table missing: ' . $table);
    }
    $have = xyptdq_columns($pdo, $database, $table);
    foreach ($required as $column) {
        if (!in_array($column, $have, true)) {
            xyptdq_adapter_fail('required column missing: ' . $table . '.' . $column);
        }
    }
}

function xyptdq_keywords(array $article): string
{
    $items = [];
    $primary = trim((string) ($article['primary_keyword'] ?? ''));
    if ($primary !== '') {
        $items[] = $primary;
    }
    foreach (($article['secondary_keywords'] ?? []) as $keyword) {
        $keyword = trim((string) $keyword);
        if ($keyword !== '' && !in_array($keyword, $items, true)) {
            $items[] = $keyword;
        }
    }
    return mb_substr(implode(',', array_slice($items, 0, 12)), 0, 255, 'UTF-8');
}

function xyptdq_article_hash(array $article): string
{
    if (!empty($article['_content_hash']) && preg_match('/^[a-f0-9]{64}$/', (string) $article['_content_hash'])) {
        return (string) $article['_content_hash'];
    }

    $copy = $article;
    foreach (['_source_file', '_publish_at_iso', '_publish_at_ts', '_content_hash'] as $internal) {
        unset($copy[$internal]);
    }
    $encoded = json_encode($copy, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    if ($encoded === false) {
        xyptdq_adapter_fail('cannot hash article JSON');
    }
    return hash('sha256', $encoded);
}

function xyptdq_load_db_config(): array
{
    $webroot = getenv('XYPTDQ_WEBROOT') ?: '/www/wwwroot/59.110.217.6';
    $configPath = getenv('XYPTDQ_DB_CONFIG') ?: $webroot . '/config/database.php';
    if (!is_file($configPath)) {
        xyptdq_adapter_fail('database config not found');
    }

    $db = [];
    require $configPath;
    $config = $db['default'] ?? null;
    if (!is_array($config)) {
        xyptdq_adapter_fail('unexpected database config format');
    }
    foreach (['hostname', 'username', 'password', 'database'] as $key) {
        if (!array_key_exists($key, $config)) {
            xyptdq_adapter_fail('database config field missing: ' . $key);
        }
    }
    return $config;
}

function xyptdq_open_pdo(array $config): PDO
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

function xyptdq_ensure_registry(PDO $pdo, string $registry): void
{
    $sql = 'CREATE TABLE IF NOT EXISTS `' . $registry . '` (
        `article_key` varchar(80) NOT NULL,
        `cms_id` int(10) unsigned NOT NULL,
        `content_hash` char(64) NOT NULL,
        `source_file` varchar(255) DEFAULT NULL,
        `published_at` int(10) unsigned NOT NULL,
        PRIMARY KEY (`article_key`),
        UNIQUE KEY `uniq_cms_id` (`cms_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci';
    $pdo->exec($sql);
}

/**
 * Resolve one Xunrui category without assuming a single installation layout.
 *
 * Resolution order:
 * 1. dedicated dr_<site>_<module>_category
 * 2. shared dr_<site>_share_category filtered by module marker when present
 * 3. an already published article using that catid (compatibility fallback)
 *
 * @return array{source:string,row:array}
 */
function xyptdq_resolve_category(
    PDO $pdo,
    string $database,
    string $prefix,
    string $module,
    string $newsTable,
    int $catid
): array {
    if (!preg_match('/^([0-9]+)_([A-Za-z0-9_]+)$/', $module, $match)) {
        xyptdq_adapter_fail('unexpected CMS module identifier: ' . $module);
    }
    $siteId = $match[1];
    $moduleName = $match[2];

    $dedicated = xyptdq_identifier($prefix . $module . '_category', 'dedicated category table');
    if (xyptdq_table_exists($pdo, $database, $dedicated)) {
        $columns = xyptdq_columns($pdo, $database, $dedicated);
        if (in_array('id', $columns, true)) {
            $select = ['id'];
            foreach (['disabled', 'name', 'dirname'] as $column) {
                if (in_array($column, $columns, true)) {
                    $select[] = $column;
                }
            }
            $sql = 'SELECT ' . implode(',', array_map(static function (string $column): string {
                return '`' . $column . '`';
            }, $select)) . ' FROM `' . $dedicated . '` WHERE `id`=:id LIMIT 1';
            $stmt = $pdo->prepare($sql);
            $stmt->execute([':id' => $catid]);
            $row = $stmt->fetch();
            if (is_array($row)) {
                if (array_key_exists('disabled', $row) && (int) $row['disabled'] !== 0) {
                    xyptdq_adapter_fail('target category is disabled: ' . $catid);
                }
                return ['source' => $dedicated, 'row' => $row];
            }
        }
    }

    $shared = xyptdq_identifier($prefix . $siteId . '_share_category', 'shared category table');
    if (xyptdq_table_exists($pdo, $database, $shared)) {
        $columns = xyptdq_columns($pdo, $database, $shared);
        if (in_array('id', $columns, true)) {
            $select = ['id'];
            foreach (['disabled', 'name', 'dirname', 'mid', 'module', 'module_name'] as $column) {
                if (in_array($column, $columns, true)) {
                    $select[] = $column;
                }
            }

            $where = '`id`=:id';
            $params = [':id' => $catid];
            $moduleColumn = null;
            foreach (['mid', 'module', 'module_name'] as $candidate) {
                if (in_array($candidate, $columns, true)) {
                    $moduleColumn = $candidate;
                    break;
                }
            }
            if ($moduleColumn !== null) {
                $where .= ' AND `' . $moduleColumn . '`=:module_name';
                $params[':module_name'] = $moduleName;
            }

            $sql = 'SELECT ' . implode(',', array_map(static function (string $column): string {
                return '`' . $column . '`';
            }, $select)) . ' FROM `' . $shared . '` WHERE ' . $where . ' LIMIT 1';
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
            $row = $stmt->fetch();
            if (is_array($row)) {
                if (array_key_exists('disabled', $row) && (int) $row['disabled'] !== 0) {
                    xyptdq_adapter_fail('target category is disabled: ' . $catid);
                }
                return ['source' => $shared, 'row' => $row];
            }
        }
    }

    $fallback = $pdo->prepare(
        'SELECT `id`,`catid`,`status` FROM `' . $newsTable . '` '
        . 'WHERE `catid`=:catid AND `status`=9 ORDER BY `id` DESC LIMIT 1'
    );
    $fallback->execute([':catid' => $catid]);
    $row = $fallback->fetch();
    if (is_array($row)) {
        return ['source' => 'existing_published_content', 'row' => $row];
    }

    xyptdq_adapter_fail('target category does not exist: ' . $catid);
}

/**
 * @return array{cms_id:int,url:string,idempotent:bool}
 */
function xyptdq_publish_article(array $article): array
{
    foreach (['article_key', 'title', 'content', 'catid'] as $field) {
        if (!array_key_exists($field, $article) || $article[$field] === '') {
            xyptdq_adapter_fail('article field missing: ' . $field);
        }
    }

    $articleKey = (string) $article['article_key'];
    if (!preg_match('/^[a-z0-9][a-z0-9_-]{2,79}$/', $articleKey)) {
        xyptdq_adapter_fail('invalid article_key');
    }

    $title = trim((string) $article['title']);
    if (mb_strlen($title, 'UTF-8') < 8 || mb_strlen($title, 'UTF-8') > 255) {
        xyptdq_adapter_fail('title length is outside CMS safety bounds');
    }

    $content = (string) $article['content'];
    if (mb_strlen(strip_tags($content), 'UTF-8') < 180) {
        xyptdq_adapter_fail('article content is too thin');
    }

    $catid = (int) $article['catid'];
    if ($catid <= 0) {
        xyptdq_adapter_fail('invalid catid');
    }

    $config = xyptdq_load_db_config();
    $database = xyptdq_identifier((string) $config['database'], 'database');
    $prefix = (string) ($config['DBPrefix'] ?? 'dr_');
    if (!preg_match('/^[A-Za-z0-9_]+$/', $prefix)) {
        xyptdq_adapter_fail('unsafe database table prefix');
    }

    $module = getenv('XYPTDQ_CMS_MODULE') ?: '1_news';
    $module = xyptdq_identifier($module, 'module');
    $newsTable = xyptdq_identifier($prefix . $module, 'news table');
    $hitsTable = xyptdq_identifier($prefix . $module . '_hits', 'hits table');
    $indexTable = xyptdq_identifier($prefix . $module . '_index', 'index table');
    $registryTable = xyptdq_identifier($prefix . 'xyptdq_publish_registry', 'registry table');

    $pdo = xyptdq_open_pdo($config);
    xyptdq_require_columns($pdo, $database, $newsTable, [
        'id', 'catid', 'title', 'thumb', 'keywords', 'description', 'hits', 'uid', 'author',
        'status', 'url', 'link_id', 'tableid', 'inputip', 'inputtime', 'updatetime', 'displayorder'
    ]);
    xyptdq_require_columns($pdo, $database, $hitsTable, [
        'id', 'hits', 'day_hits', 'week_hits', 'month_hits', 'year_hits',
        'day_time', 'week_time', 'month_time', 'year_time'
    ]);
    xyptdq_require_columns($pdo, $database, $indexTable, ['id', 'uid', 'catid', 'status', 'inputtime']);
    xyptdq_ensure_registry($pdo, $registryTable);

    $resolvedCategory = xyptdq_resolve_category(
        $pdo,
        $database,
        $prefix,
        $module,
        $newsTable,
        $catid
    );
    if (empty($resolvedCategory['source'])) {
        xyptdq_adapter_fail('category resolution returned no source');
    }

    $partitionStmt = $pdo->prepare(
        'SELECT tableid,uid,author FROM `' . $newsTable . '` WHERE catid=:catid ORDER BY id DESC LIMIT 1'
    );
    $partitionStmt->execute([':catid' => $catid]);
    $known = $partitionStmt->fetch();
    $tableId = is_array($known) ? (int) ($known['tableid'] ?? 0) : 0;
    if ($tableId < 0 || $tableId > 9999) {
        xyptdq_adapter_fail('unsafe CMS data table partition');
    }

    $dataTable = xyptdq_identifier($prefix . $module . '_data_' . $tableId, 'data table');
    xyptdq_require_columns($pdo, $database, $dataTable, ['id', 'uid', 'catid', 'content']);

    $uid = max(1, (int) (getenv('XYPTDQ_CMS_UID') ?: (is_array($known) ? ($known['uid'] ?? 1) : 1)));
    $author = trim((string) ($article['author'] ?? ''));
    if ($author === '') {
        $author = trim((string) (getenv('XYPTDQ_CMS_AUTHOR') ?: (is_array($known) ? ($known['author'] ?? '老彩迷编辑') : '老彩迷编辑')));
    }
    $author = mb_substr($author !== '' ? $author : '老彩迷编辑', 0, 50, 'UTF-8');

    $thumb = mb_substr(trim((string) ($article['thumbnail'] ?? '')), 0, 255, 'UTF-8');
    $keywords = xyptdq_keywords($article);
    $description = trim((string) ($article['meta_description'] ?? $article['excerpt'] ?? ''));
    $contentHash = xyptdq_article_hash($article);
    $sourceFile = mb_substr((string) ($article['_source_file'] ?? ''), 0, 255, 'UTF-8');
    $now = time();

    $pdo->beginTransaction();
    try {
        $existingStmt = $pdo->prepare(
            'SELECT article_key,cms_id,content_hash FROM `' . $registryTable . '` WHERE article_key=:key FOR UPDATE'
        );
        $existingStmt->execute([':key' => $articleKey]);
        $existing = $existingStmt->fetch();

        if (is_array($existing)) {
            if (!hash_equals((string) $existing['content_hash'], $contentHash)) {
                throw new RuntimeException('published article_key exists with a different content hash: ' . $articleKey);
            }
            $cmsId = (int) $existing['cms_id'];
            $checkStmt = $pdo->prepare('SELECT id,url FROM `' . $newsTable . '` WHERE id=:id LIMIT 1');
            $checkStmt->execute([':id' => $cmsId]);
            $cmsRow = $checkStmt->fetch();
            if (!is_array($cmsRow)) {
                throw new RuntimeException('idempotency registry points to missing CMS article: ' . $cmsId);
            }
            $pdo->commit();
            return [
                'cms_id' => $cmsId,
                'url' => (string) ($cmsRow['url'] ?? ('/index.php?c=show&id=' . $cmsId)),
                'idempotent' => true,
            ];
        }

        $insertNews = $pdo->prepare(
            'INSERT INTO `' . $newsTable . '` '
            . '(catid,title,thumb,keywords,description,hits,uid,author,status,url,link_id,tableid,inputip,inputtime,updatetime,displayorder) '
            . 'VALUES (:catid,:title,:thumb,:keywords,:description,0,:uid,:author,9,\'\',0,:tableid,:inputip,:inputtime,:updatetime,0)'
        );
        $insertNews->execute([
            ':catid' => $catid,
            ':title' => $title,
            ':thumb' => $thumb,
            ':keywords' => $keywords,
            ':description' => $description,
            ':uid' => $uid,
            ':author' => $author,
            ':tableid' => $tableId,
            ':inputip' => '127.0.0.1',
            ':inputtime' => $now,
            ':updatetime' => $now,
        ]);

        $cmsId = (int) $pdo->lastInsertId();
        if ($cmsId <= 0) {
            throw new RuntimeException('CMS main table did not return a new id');
        }

        $url = '/index.php?c=show&id=' . $cmsId;
        $pdo->prepare('UPDATE `' . $newsTable . '` SET url=:url WHERE id=:id')
            ->execute([':url' => $url, ':id' => $cmsId]);

        $pdo->prepare(
            'INSERT INTO `' . $dataTable . '` (id,uid,catid,content) VALUES (:id,:uid,:catid,:content)'
        )->execute([
            ':id' => $cmsId,
            ':uid' => $uid,
            ':catid' => $catid,
            ':content' => $content,
        ]);

        // Native PDO/MySQL prepared statements do not permit reusing one named
        // placeholder multiple times in the same statement. The previous
        // :now,:now,:now,:now form therefore raised SQLSTATE[HY093] when
        // ATTR_EMULATE_PREPARES=false. Bind each timestamp placeholder once.
        $pdo->prepare(
            'INSERT INTO `' . $hitsTable . '` '
            . '(id,hits,day_hits,week_hits,month_hits,year_hits,day_time,week_time,month_time,year_time) '
            . 'VALUES (:id,0,0,0,0,0,:day_time,:week_time,:month_time,:year_time)'
        )->execute([
            ':id' => $cmsId,
            ':day_time' => $now,
            ':week_time' => $now,
            ':month_time' => $now,
            ':year_time' => $now,
        ]);

        $pdo->prepare(
            'INSERT INTO `' . $indexTable . '` (id,uid,catid,status,inputtime) '
            . 'VALUES (:id,:uid,:catid,9,:inputtime)'
        )->execute([
            ':id' => $cmsId,
            ':uid' => $uid,
            ':catid' => $catid,
            ':inputtime' => $now,
        ]);

        $pdo->prepare(
            'INSERT INTO `' . $registryTable . '` '
            . '(article_key,cms_id,content_hash,source_file,published_at) '
            . 'VALUES (:article_key,:cms_id,:content_hash,:source_file,:published_at)'
        )->execute([
            ':article_key' => $articleKey,
            ':cms_id' => $cmsId,
            ':content_hash' => $contentHash,
            ':source_file' => $sourceFile,
            ':published_at' => $now,
        ]);

        $pdo->commit();
        return ['cms_id' => $cmsId, 'url' => $url, 'idempotent' => false];
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $e;
    }
}

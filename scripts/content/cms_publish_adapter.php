<?php
/**
 * Compatibility entrypoint for the production Xunrui publisher.
 *
 * The former direct-SQL content writer is intentionally retired. All content
 * creation now delegates to cms_publish_native_adapter.php, which uses Xunrui's
 * own save_content lifecycle and verifies the shared routing index.
 */
declare(strict_types=1);

require_once __DIR__ . '/cms_publish_native_adapter.php';

// Compatibility wrappers retained for existing smoke/probe scripts. No wrapper
// below writes CMS content directly.
if (!function_exists('xyptdq_adapter_fail')) {
    function xyptdq_adapter_fail(string $message): void { xyptdq_native_fail($message); }
}
if (!function_exists('xyptdq_identifier')) {
    function xyptdq_identifier(string $value, string $label): string { return xyptdq_native_identifier($value, $label); }
}
if (!function_exists('xyptdq_table_exists')) {
    function xyptdq_table_exists(PDO $pdo, string $database, string $table): bool { return xyptdq_native_table_exists($pdo, $database, $table); }
}
if (!function_exists('xyptdq_columns')) {
    function xyptdq_columns(PDO $pdo, string $database, string $table): array { return xyptdq_native_columns($pdo, $database, $table); }
}
if (!function_exists('xyptdq_require_columns')) {
    function xyptdq_require_columns(PDO $pdo, string $database, string $table, array $required): void { xyptdq_native_require_columns($pdo, $database, $table, $required); }
}
if (!function_exists('xyptdq_article_hash')) {
    function xyptdq_article_hash(array $article): string { return xyptdq_native_article_hash($article); }
}
if (!function_exists('xyptdq_load_db_config')) {
    function xyptdq_load_db_config(): array { return xyptdq_native_load_db_config(); }
}
if (!function_exists('xyptdq_open_pdo')) {
    function xyptdq_open_pdo(array $config): PDO { return xyptdq_native_open_pdo($config); }
}
if (!function_exists('xyptdq_ensure_registry')) {
    function xyptdq_ensure_registry(PDO $pdo, string $registry): void { xyptdq_native_ensure_registry($pdo, $registry); }
}
if (!function_exists('xyptdq_resolve_category')) {
    function xyptdq_resolve_category(PDO $pdo, string $database, string $prefix, string $module, string $newsTable, int $catid): array
    {
        return xyptdq_native_resolve_category($pdo, $database, $prefix, $module, $newsTable, $catid);
    }
}

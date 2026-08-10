<?php
/**
 * Xunrui-native content publisher body executed inside the CMS API context.
 * Based on the official Xunrui content collection pattern: initialize the
 * module, split fields by main/data tables, then call save_content(0, $save).
 */

if (PHP_SAPI !== 'cli') {
    exit;
}

$this->_module_init('news');

$articleFile = getenv('XYPTDQ_NATIVE_ARTICLE_FILE') ?: '';
$contentRoot = getenv('XYPTDQ_REPO_CONTENT_ROOT') ?: '/opt/xyptdq-repo/content';
$rootReal = realpath($contentRoot);
$fileReal = $articleFile !== '' ? realpath($articleFile) : false;
if (!$rootReal || !$fileReal || strpos($fileReal, $rootReal . DIRECTORY_SEPARATOR) !== 0) {
    echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
        'ok' => false,
        'error' => 'ARTICLE_PATH_REJECTED',
    ])) . PHP_EOL;
    exit;
}

$article = json_decode((string) file_get_contents($fileReal), true);
if (!is_array($article)) {
    echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
        'ok' => false,
        'error' => 'ARTICLE_JSON_INVALID',
    ])) . PHP_EOL;
    exit;
}

foreach (['article_key', 'title', 'content', 'catid'] as $required) {
    if (!isset($article[$required]) || $article[$required] === '') {
        echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
            'ok' => false,
            'error' => 'ARTICLE_FIELD_MISSING',
            'field' => $required,
        ])) . PHP_EOL;
        exit;
    }
}

$catid = (int) $article['catid'];
if ($catid <= 0) {
    echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
        'ok' => false,
        'error' => 'CATID_INVALID',
    ])) . PHP_EOL;
    exit;
}

// Load the module category cache exactly as the official collection example.
$this->module['category'] = \Phpcmf\Service::L('category', 'module')->get_category(
    $this->module['share'] ? 'share' : $this->module['dirname']
);
if (empty($this->module['category'][$catid])) {
    echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
        'ok' => false,
        'error' => 'CATEGORY_NOT_VISIBLE_TO_CMS',
        'catid' => $catid,
    ])) . PHP_EOL;
    exit;
}

$data = [
    'title' => trim((string) $article['title']),
    'content' => (string) $article['content'],
    'thumb' => trim((string) ($article['thumbnail'] ?? '')),
    'keywords' => trim((string) ($article['primary_keyword'] ?? '')),
    'description' => trim((string) ($article['meta_description'] ?? $article['excerpt'] ?? '')),
    'uid' => 1,
    'author' => trim((string) ($article['author'] ?? '老彩迷编辑')) ?: '老彩迷编辑',
    'catid' => $catid,
];

if (!empty($article['secondary_keywords']) && is_array($article['secondary_keywords'])) {
    $keywords = [];
    if ($data['keywords'] !== '') {
        $keywords[] = $data['keywords'];
    }
    foreach ($article['secondary_keywords'] as $keyword) {
        $keyword = trim((string) $keyword);
        if ($keyword !== '' && !in_array($keyword, $keywords, true)) {
            $keywords[] = $keyword;
        }
    }
    $data['keywords'] = mb_substr(implode(',', array_slice($keywords, 0, 12)), 0, 255, 'UTF-8');
}

$fields = [];
$fields[1] = $this->get_cache(
    'table-' . SITE_ID,
    $this->content_model->dbprefix(SITE_ID . '_' . MOD_DIR)
);
$categoryFields = $this->get_cache(
    'table-' . SITE_ID,
    $this->content_model->dbprefix(SITE_ID . '_' . MOD_DIR . '_category_data')
);
if ($categoryFields) {
    $fields[1] = array_merge($fields[1], $categoryFields);
}
$fields[0] = $this->get_cache(
    'table-' . SITE_ID,
    $this->content_model->dbprefix(SITE_ID . '_' . MOD_DIR . '_data_0')
);
$fields[0] = array_unique((array) $fields[0]);
$fields[1] = array_unique((array) $fields[1]);

$save = [0 => [], 1 => []];
foreach ($fields as $isMain => $fieldNames) {
    foreach ($fieldNames as $name) {
        if (array_key_exists($name, $data)) {
            $save[$isMain][$name] = $data[$name];
        }
    }
}

$save[1]['uid'] = $save[0]['uid'] = 1;
$save[1]['catid'] = $save[0]['catid'] = $catid;
$save[1]['author'] = $data['author'];
$save[1]['url'] = '';
$save[1]['status'] = 9;
$save[1]['hits'] = 0;
$save[1]['displayorder'] = 0;
$save[1]['link_id'] = 0;
$save[1]['inputtime'] = SYS_TIME;
$save[1]['updatetime'] = SYS_TIME;
$save[1]['inputip'] = '127.0.0.1';

if (empty($save[1]['title']) || empty($save[0]['content'])) {
    echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
        'ok' => false,
        'error' => 'CMS_FIELD_SPLIT_INCOMPLETE',
    ])) . PHP_EOL;
    exit;
}

// Do not create a duplicate test article if the title already exists.
if ($this->content_model->table(SITE_ID . '_' . MOD_DIR)->where('title', $save[1]['title'])->counts()) {
    echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
        'ok' => false,
        'error' => 'TITLE_ALREADY_EXISTS',
    ])) . PHP_EOL;
    exit;
}

$rt = $this->content_model->save_content(0, $save);
$cmsId = isset($rt['code']) ? (int) $rt['code'] : 0;
if ($cmsId <= 0) {
    echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
        'ok' => false,
        'error' => 'SAVE_CONTENT_FAILED',
    ])) . PHP_EOL;
    exit;
}

echo 'XYPTDQ_NATIVE_RESULT=' . base64_encode(json_encode([
    'ok' => true,
    'cms_id' => $cmsId,
    'catid' => $catid,
])) . PHP_EOL;
exit;

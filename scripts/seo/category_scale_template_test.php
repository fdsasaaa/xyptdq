#!/usr/bin/env php
<?php
declare(strict_types=1);

function categoryScaleFail(string $message): void
{
    fwrite(STDERR, '[category-scale-template-test] FAIL: ' . $message . PHP_EOL);
    exit(1);
}

$root = dirname(__DIR__, 2);
$pcHeader = (string) file_get_contents($root . '/site/template/pc/default/home/seo_header.html');
$mobileHeader = (string) file_get_contents($root . '/site/template/mobile/default/home/seo_header.html');
$pcList = (string) file_get_contents($root . '/site/template/pc/default/home/list.html');
$mobileList = (string) file_get_contents($root . '/site/template/mobile/default/home/list.html');

foreach (['pc' => $pcHeader, 'mobile' => $mobileHeader] as $name => $src) {
    foreach ([
        '$xyptdq_is_category && $xyptdq_request_page > 1',
        "\$xyptdq_page_label = '第' . \$xyptdq_request_page . '页'",
        "\$xyptdq_title .= '｜' . \$xyptdq_page_label",
        "\$xyptdq_desc .= ' 当前为' . \$xyptdq_page_label . '。'",
        "\$xyptdq_canonical .= '&page=' . \$xyptdq_request_page",
    ] as $needle) {
        if (strpos($src, $needle) === false) {
            categoryScaleFail($name . ' paginated metadata marker missing: ' . $needle);
        }
    }
}

foreach ([
    '{module catid=$catid order=updatetime num=8}',
    '{module catid=$catid order=hits num=8}',
] as $needle) {
    if (strpos($pcList, $needle) === false) {
        categoryScaleFail('PC current-category sidebar marker missing: ' . $needle);
    }
}
foreach ([
    '{module module=news order=updatetime num=8}',
    '{module module=news order=hits num=8}',
] as $needle) {
    if (strpos($pcList, $needle) !== false) {
        categoryScaleFail('PC sidebar still contains cross-category query: ' . $needle);
    }
}

if (strpos($mobileList, 'xyptdq-mobile-pagination') === false || strpos($mobileList, '{$pages}') === false) {
    categoryScaleFail('mobile crawlable pagination output is missing');
}
if (strpos($mobileList, 'dr_ajax_load_more') === false || strpos($mobileList, 'id="is_ajax_btn"') === false) {
    categoryScaleFail('mobile load-more experience was removed');
}

fwrite(STDOUT, "[category-scale-template-test] PASS pagination_meta=unique sidebar=current_category mobile_links=crawlable load_more=preserved\n");

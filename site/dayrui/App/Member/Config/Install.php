<?php

\Phpcmf\Service::M('Menu')->db->resetDataCache();
\Phpcmf\Service::M('Menu')->db->table('member_menu')->truncate();
\Phpcmf\Service::M('Menu')->db->table('member_menu')->emptyTable();

$menu = require $path.'Config/Menu.php';
foreach ($menu['member'] as $mark => $top) {
    // 插入顶级菜单
    $mark = strlen($mark) > 2 ? $mark : '';
    $top_id = \Phpcmf\Service::M('Menu')->_add('member', 0, $top, $mark, true);
    // 插入链接菜单
    if ($top_id) {
        foreach ($top['link'] as $mark2 => $link) {
            \Phpcmf\Service::M('Menu')->_add('member', $top_id, $link);
        }
    }
}

<?php

\Phpcmf\Hooks::app_on('member', 'cms_init', function() {

    if (IS_ADMIN || IS_API) {
        return;
    }

    \Phpcmf\Service::L('member', 'member')->group_timeout(\Phpcmf\Service::C());

});


// 多几个版本再移动至init
if (!function_exists('dr_member_menu_show')) {

    // 判断用户中心菜单权限
    function dr_member_menu_show($t) {

        if ($t['mark']) {
            list($a, $b) = explode('-', $t['mark']);
            switch ($a) {
                case 'module':
                    // 判断模块当前站点是否可用
                    if (!\Phpcmf\Service::C()->get_cache('module-'.SITE_ID.'-'.$b)) {
                        return 0;
                    }
                    break;
            }
        }

        // 判断站点显示权限
        $is_site = 0;
        if (!$t['site'] || ($t['site'] && dr_in_array(SITE_ID, $t['site']))) {
            $is_site = 1; // 当前可用
        }

        // 判断终端显示权限
        $is_client = 0;
        if (!$t['client'] || ($t['client'] && dr_in_array(CLIENT_NAME, $t['client']))) {
            $is_client = 1; // 当前可用
        }

        // 判断用户组显示权限
        if ($is_client && $is_site
            && (!$t['group'] || dr_array_intersect(\Phpcmf\Service::C()->member['groupid'], $t['group']))) {
            return 1;
        }

        return 0;
    }

}

if (!function_exists('dr_member_group_is_timeout')) {
    function dr_member_group_is_timeout() {

        if (APP_DIR == 'api' or IS_API == 1) {
            return 0; // api控制器不强制跳转
        } elseif (APP_DIR == 'pay') {
            return 0; // 支付系统放过
        } elseif (IS_MEMBER
            && in_array(\Phpcmf\Service::L('Router')->class, ['home', 'pay', 'recharge', 'api', 'apply'])) {
            return 0;// 指定这些控制器不强制跳转
        }

        return 1;
    }
}
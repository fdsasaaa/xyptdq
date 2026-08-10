<?php namespace Phpcmf\Controllers\Admin;


class Field extends \Phpcmf\Common {

    public function index() {

        $list = [];
        $local = \Phpcmf\Service::Apps();
        foreach ($local as $dir => $path) {
            if (is_file(dr_get_app_dir($dir).'Config/App.php')) {
                $key = strtolower($dir);
                $cfg = require dr_get_app_dir($dir).'Config/App.php';
                if ($cfg['type'] == 'module' || $cfg['ftype'] == 'module') {
                    if (isset($cfg['hlist']) && $cfg['hlist']) {
                        // 不在列表显示
                        continue;
                    }
                    $cfg['dirname'] = $key;
                    $list[$key] = $cfg;
                }
            }
        }

        $my = [];
        $module = \Phpcmf\Service::M('Module')->All(); // 库中已安装模块
        if ($module) {
            foreach ($module as $t) {
                $dir = $t['dirname'];
                if ($list[$dir]) {
                    $t['name'] = dr_lang($list[$dir]['name']);
                    $t['mtype'] = $list[$dir]['mtype'];
                    $t['system'] = $list[$dir]['system'];
                    $t['version'] = $list[$dir]['version'];
                    $site = dr_string2array($t['site']);
                    $t['install'] = isset($site[SITE_ID]) && $site[SITE_ID] ? 1 : 0;
                    $my[$dir] = $t;
                    unset($list[$dir]);
                }
            }
        }

        \Phpcmf\Service::V()->assign([
            'my' => $my,
            'list' => $list,
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '自定义字段' => [APP_DIR.'/field/index', 'fa fa-code'],
                ]
            ),
        ]);
        \Phpcmf\Service::V()->display('field.html');
    }


}

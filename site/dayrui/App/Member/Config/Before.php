<?php

$code = (string)file_get_contents(CMSPATH.'Core/Hooks.php');
if (strpos($code, 'app_on') === false) {
    return dr_return_data(0, 'CMS主程序版本较低，无法安装本插件');
}

if (\Phpcmf\Service::M()->is_table_exists('member_menu')) {
    $path = dr_get_app_dir('member');
    file_put_contents($path.'install.lock', SYS_TIME);
    // 已经安装成功的版本
    \Phpcmf\Service::M('Menu')->add_app('member');
    return dr_return_data(0, '用户系统已安装成功');
}

return dr_return_data(1, 'ok');
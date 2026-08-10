<?php namespace Phpcmf\Controllers;

$file = dr_get_app_dir('pay').'Controllers/Member/Paylog.php';
if (is_file($file)) {
    require_once $file;
} else {
    \dr_exit_msg(0, '没有安装「支付系统」插件');
}

class Paylog extends \Phpcmf\Controllers\Member\Paylog
{


}


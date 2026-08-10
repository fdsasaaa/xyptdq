<?php namespace Phpcmf\Controllers;

$file = dr_get_app_dir('pay').'Controllers/Member/Pay.php';
if (is_file($file)) {
    require_once $file;
} else {
    \dr_exit_msg(0, '没有安装「支付系统」插件');
}

// 付款
class Pay extends \Phpcmf\Controllers\Member\Pay
{


}

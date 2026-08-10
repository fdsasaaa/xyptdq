<?php namespace Phpcmf\Model\Mbdy;

// 权限验证
class Auth extends \Phpcmf\Model\Auth
{

    // 判断底部链接的显示权限
    public function is_bottom_auth($mid) {


        return 1;
    }

    // 判断右侧链接的显示权限
    public function is_link_auth($mid) {

        return 1;
    }

}
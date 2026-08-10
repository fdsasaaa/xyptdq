<?php

if (IS_ADMIN) {
    if (! function_exists('dr_redirect_safe_check')) {
        $this->_admin_msg(1, '需要升级一下CMS主程序！', dr_url('cloud/update'));
    }
}


// 头像
function dr_member_list_avatar($value, $param = [], $data = [], $field = []) {

    $uid = isset($data['id']) ? $data['id'] : 0;

    return '<a class="fc_member_show" href="javascript:;" uid="'.$uid.'"><img class="img-circle" src="'.dr_avatar($uid).'" style="width:30px;height:30px"></a>';
}

function dr_member_verify_avatar_url($uid) {

    $avatar_url = '';
    list($cache_path, $cache_url) = dr_avatar_path();
    $dir = dr_avatar_dir($uid);
    if (is_file($cache_path.$dir.$uid.'_verify.jpg')) {
        $avatar_url = $cache_url.$dir.$uid.'_verify.jpg?time='.SYS_TIME;
    }

    return $avatar_url;
}

// 头像
function dr_member_verify_avatar($value, $param = [], $data = [], $field = []) {

    $uid = isset($data['uid']) ? $data['uid'] : 0;

    return '<a class="fc_member_show" href="javascript:;" uid="'.$uid.'"><img class="img-circle" src="'.dr_avatar($uid).'" style="width:30px;height:30px"></a>';
}
function dr_member_verify_avatar2($value, $param = [], $data = [], $field = []) {

    $uid = isset($data['uid']) ? $data['uid'] : 0;
    return '<a href="javascript:;""><img class="img-circle" src="'.dr_member_verify_avatar_url($uid).'" style="width:30px;height:30px"></a>';
}

function dr_member_verify_status($value, $param = [], $data = [], $field = []) {

    if ($value == 1) {
        $html = '<span class="label label-sm label-danger">'.dr_lang('待审核');
    } elseif ($value == 2) {
        $html = '<span class="label label-sm label-success">'.dr_lang('已通过');
    } else {
        $html = '<span class="label label-sm label-warning">'.dr_lang('未通过') ;
    }

    return '<label>'.$html.'</span></label>';

}
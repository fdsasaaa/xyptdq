<?php
// 自定义字段的支持函数
// \Phpcmf\Service::M('field')


// 初始化信息
function myfield_init_member($relatedname, $relatedid) {
    return dr_return_data(1, 'ok', [
        'ismain' => 1,
        'name' => '用户信息字段',
        'backurl' => \Phpcmf\Service::L('Router')->url('member/field/index'), // 返回uri地址
    ]);
}
function myfield_tablename_member($field, $siteid, $relatedname, $relatedid) {
    return 'member_data';
}

// 执行sql
function myfield_sql_member($sql, $ismain) {
    \Phpcmf\Service::M('field')->db->simpleQuery(str_replace('{tablename}', \Phpcmf\Service::M('field')->dbprefix('member_data'), $sql));
    \Phpcmf\Service::M('field')->_table_field[] = \Phpcmf\Service::M('field')->dbprefix('member_data');
}
// 字段是否存在
function myfield_field_member($name) {
    // 保留
    if (in_array($name, ['role', 'uid', 'authid', 'adminid', 'tableid', 'group', 'groupid', 'levelid'])) {
        return 1;
    }
    // 主表
    $table = \Phpcmf\Service::M('field')->dbprefix('member_data');
    $rt = \Phpcmf\Service::M('field')->_field_exitsts('id', $name, $table, SITE_ID);
    if ($rt) {
        return 1;
    }
    return 0;
}
// 更新缓存
function myfield_cache_member() {
    \Phpcmf\Service::M('cache')->sync_cache('member'); // 自动更新缓存
}
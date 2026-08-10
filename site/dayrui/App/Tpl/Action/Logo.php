<?php
if (!defined('BASEPATH')) exit('No direct script access allowed');


$logo = [
    'logo' => [
        'ismain' => 1,
        'fieldtype' => 'File',
        'fieldname' => 'logo',
        'setting' => ['option' => ['ext' => 'jpg,gif,png,jpeg,webp,svg', 'size' => 10, 'input' => 1]]
    ]
];

// 初始化自定义字段类
\Phpcmf\Service::L('Field')->app('');

$data = \Phpcmf\Service::M('Site')->config(SITE_ID);

if (IS_AJAX_POST) {

    $post = \Phpcmf\Service::L('input')->post('data');

    $data['logo'] = $post['logo'];
    $rt = \Phpcmf\Service::M('Site')->config(SITE_ID, 'config', $data);
    if (!is_array($rt)) {
        $this->_json(0, dr_lang('项目信息(#%s)不存在', SITE_ID));
    }
    // 附件归档
    if (SYS_ATTACHMENT_DB) {
        list($post, $return, $attach) = \Phpcmf\Service::L('form')->validation($post, null, []);
        $attach && \Phpcmf\Service::M('Attachment')->handle($this->member['id'], \Phpcmf\Service::M()->dbprefix('site'), $attach);
    }

    \Phpcmf\Service::L('input')->system_log('设置项目LOGO参数');
    \Phpcmf\Service::M('cache')->sync_cache('');
    $this->_json(1, dr_lang('操作成功'));
}


\Phpcmf\Service::V()->assign([
    'form' => dr_form_hidden(),
    'myfield' => dr_fieldform($logo['logo'], $data['config']['logo']),
]);

\Phpcmf\Service::V()->display('dev_edit.html');
<?php
if (!defined('BASEPATH')) exit('No direct script access allowed');


$data = \Phpcmf\Service::M('Site')->config(SITE_ID);

if ($p == 'logo') {
    $field = [
        'logo' => [
            'ismain' => 1,
            'fieldtype' => 'File',
            'fieldname' => 'logo',
            'setting' => ['option' => ['ext' => 'jpg,gif,png,jpeg,webp,svg', 'size' => 10, 'input' => 1]]
        ]
    ];
    $value = $data['config'];
} else {
    $row = \Phpcmf\Service::M('field')->get_mysite_field(SITE_ID);
    if (isset($row[$p]) && $row[$p]) {
        $field = [
            $p => $row[$p],
        ];
        $value = $data['param'];
    } else {
        dr_redirect(dr_url('site_param/index', ['show_field' => $p]));exit;
    }
}


// 初始化自定义字段类
\Phpcmf\Service::L('Field')->app('');

if (IS_AJAX_POST) {

    $post = \Phpcmf\Service::L('input')->post('data');

    // param
    if ($p == 'logo') {
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

        \Phpcmf\Service::L('input')->system_log('设置项目自定义参数');
    } else {
        list($save, $return, $attach, $notfield) = \Phpcmf\Service::L('form')->validation($post, null, $field, $data['param']);
        // 输出错误
        if ($return) {
            $this->_json(0, $return['error'], ['field' => $return['name']]);
        }
        foreach ($save[1] as $key => $val) {
            $data['param'][$key] = $val;
        }
        $rt = \Phpcmf\Service::M('Site')->config(
            SITE_ID,
            'param',
            $data['param']
        );
        if (!is_array($rt)) {
            $this->_json(0, dr_lang('项目信息(#%s)不存在', SITE_ID));
        }
        // 附件归档
        if (SYS_ATTACHMENT_DB) {
            $attach && \Phpcmf\Service::M('Attachment')->handle($this->member['id'], \Phpcmf\Service::M()->dbprefix('site'), $attach);
        }
    }


    \Phpcmf\Service::M('cache')->sync_cache('');
    $this->_json(1, dr_lang('操作成功'));
}

$page = intval(\Phpcmf\Service::L('input')->get('page'));

\Phpcmf\Service::V()->assign([
    'form' => dr_form_hidden(),
    'myfield' => \Phpcmf\Service::L('Field')->toform(0, $field, $value),
]);

\Phpcmf\Service::V()->display('dev_edit.html');
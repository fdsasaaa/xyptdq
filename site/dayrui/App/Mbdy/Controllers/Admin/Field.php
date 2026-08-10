<?php namespace Phpcmf\Controllers\Admin;

class Field extends \Phpcmf\App
{

    public function index() {

        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '自定义字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'field' => \Phpcmf\Service::L('Field')->app()->type(''),
        ]);
        \Phpcmf\Service::V()->display('field.html');
    }


    public function tag() {

        $html = '';
        $post = \Phpcmf\Service::L('input')->xss_clean($_POST);
        if (!$post) {
            exit('字段参数没过来');
        }
        $fid = dr_safe_filename($post['field']);
        if (!$fid) {
            $this->_json(1, '字段参数没过来');
        }

        $field = $this->get_field();

        $field = $field[$fid];
        if (!$field) {
            $this->_json(1, '字段['.$fid.']不存在');
        }


        $html = \Phpcmf\Service::M('code', APP_DIR)->get_site_field_code($field);

        $this->_json(1, $html);

    }

}

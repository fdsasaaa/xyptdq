<?php namespace Phpcmf\Controllers\Admin;

class Form extends \Phpcmf\App
{


    private function get_field($field) {
        $field['inputtime'] = [
            'name' => dr_lang('录入时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'inputtime',
        ];
        $field['title'] = [
            'name' => dr_lang('主题'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'title',
        ];
        $field['uid'] = [
            'name' => dr_lang('账号'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Uid',
            'fieldname' => 'uid',
        ];
        return $field;
    }

    public function index() {

        $module = \Phpcmf\Service::L('cache')->get('form-'.SITE_ID);
        if (!$module) {
            $this->_admin_msg(0, dr_lang('系统没有创建网站表单'));
        }

        $mid = dr_safe_filename($_GET['mid']);
        if (!$mid) {
            $one = reset($module);
            $mid = $one['table'];
        }

        if (!$module[$mid]) {
            $this->_admin_msg(0, dr_lang('网站表单['.$mid.']不存在'));
        }

        $mdata = $module[$mid];

        $field = $this->get_field($mdata['field']);
        // 默认字段


        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '网站表单字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'mid' => $mid,
            'my' => $module[$mid],
            'field' => $field,
            'module' => $module,
        ]);
        \Phpcmf\Service::V()->display('form.html');
    }

    public function tag() {

        $html = '';
        $post = \Phpcmf\Service::L('input')->xss_clean($_POST);
        if (!$post) {
            exit('字段参数没过来');
        }
        $fid = dr_safe_filename($post['field']);
        if (!$fid) {
            exit('字段参数没过来');
        }
        $mid = dr_safe_filename($_GET['mid']);
        $mdata = \Phpcmf\Service::L('cache')->get('form-'.SITE_ID, $mid);
        $fields = $this->get_field($mdata['field']);
        $field = $fields[$fid];
        if (!$field) {
            exit('字段['.$fid.']不存在');
        }

        switch (intval($_GET['id'])) {

            case 1:
                // show.html字段



                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'form', '');



                break;

            case 2:

                //list.html
                $rt = dr_safe_filename($post['return']);
                if (!$rt) {
                    exit('必须填写返回变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'form',  $rt);


                break;


        }

        $this->_json(1, $html);

    }

}

<?php namespace Phpcmf\Controllers\Admin;

class Mform extends \Phpcmf\App
{

    private function get_field($field) {
        $field['inputtime'] = [
            'name' => dr_lang('录入时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'inputtime',
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

        $module = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-content');
        if (!$module) {
            $this->_admin_msg(0, dr_lang('系统没有安装内容模块'));
        }

        $mid = dr_safe_filename($_GET['mid']);
        if (!$mid) {
            $one = reset($module);
            $mid = $one['dirname'];
        }

        if (!$module[$mid]) {
            $this->_admin_msg(0, dr_lang('模块['.$mid.']不存在'));
        }

        $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$mid);

        // 默认字段
        $field = $this->get_field($mdata['field']);

        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '模块字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'mid' => $mid,
            'my' => $mdata,
            'field' => $field,
            'module' => $module,
        ]);
        \Phpcmf\Service::V()->display('mform.html');
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
        $tid = dr_safe_filename($_GET['tid']);
        $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$mid, 'form', $tid);


        $fields = $this->get_field($mdata['field']);

        $field = $fields[$fid];
        if (!$field) {
            exit('字段['.$fid.']不存在');
        }

        switch (intval($_GET['id'])) {

            case 1:
                // show.html字段

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'mform', '');


                break;

            case 2:

                //list.html
                $rt = dr_safe_filename($post['return']);
                if (!$rt) {
                    exit('必须填写返回变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'mform',  $rt);


                break;


        }

        $this->_json(1, $html);

    }

}

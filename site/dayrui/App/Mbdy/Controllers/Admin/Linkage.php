<?php namespace Phpcmf\Controllers\Admin;

class Linkage extends \Phpcmf\App
{

    private function get_field($field) {
        $field['name'] = [
            'name' => dr_lang('名称'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'title',
        ];
        return $field;
    }

    public function index() {

        $linkage = \Phpcmf\Service::M('Linkage')->table('linkage')->getAll();
        if (!$linkage) {
            $this->_admin_msg(0, dr_lang('系统没有创建联动菜单'));
        }

        $module = [];
        if ($linkage) {
            foreach ($linkage as $t) {
                $module[$t['code']] = $t;
            }
        }

        $mid = dr_safe_filename($_GET['mid']);
        if (!$mid) {
            $one = reset($module);
            $mid = $one['code'];
        }

        if (!$module[$mid]) {
            $this->_admin_msg(0, dr_lang('网站表单['.$mid.']不存在'));
        }

        $mdata = $module[$mid];

        $field = \Phpcmf\Service::M('Linkage')->get_fields($mdata['id']);
        $field = $this->get_field($field);


        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '联动菜单字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'mid' => $mid,
            'my' => $module[$mid],
            'field' => $field,
            'module' => $module,
        ]);
        \Phpcmf\Service::V()->display('linkage.html');
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
        $linkage = \Phpcmf\Service::M('Linkage')->table('linkage')->where('code', $mid)->getRow();


        $fields = \Phpcmf\Service::M('Linkage')->get_fields($linkage['id']);
        $fields = $this->get_field($fields);

        if (!$fields[$fid]) {
            exit('字段['.$fid.']不存在');
        }

        $field = $this->get_field($fields[$fid]);

        switch (intval($_GET['id'])) {

            case 1:

                $rt = ($post['id']);
                if (!$rt) {
                    exit('必须填写联动值变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_linkage_field_code($field, $mid, $rt);

                break;

            case 2:

                //list.html
                $rt = dr_safe_filename($post['return']);
                if (!$rt) {
                    exit('必须填写返回变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'linkage',  $rt);


                break;


        }

        $this->_json(1, $html);

    }

}

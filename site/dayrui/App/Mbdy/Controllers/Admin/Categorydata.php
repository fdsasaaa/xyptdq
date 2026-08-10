<?php namespace Phpcmf\Controllers\Admin;

class Categorydata extends \Phpcmf\App
{

    private $mrfield = [
    ];

    public function index() {


        $content = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-content');

        $module = [
        ];
        if ($content) {
            foreach ($content as $i => $t) {
                $module[$i] = $t;
            }
        }

        $mid = dr_safe_filename($_GET['mid']);
        if (!$mid) {
            $one = reset($module);
            $mid = $one['dirname'];
        }

        if ($mid && !$module[$mid]) {
            $this->_admin_msg(0, dr_lang('模块['.$mid.']不存在'));
        }

        $like = ['catmodule-'.$mid];
        if ($module[$mid]['share']) {
            $like[] = 'catmodule-share';
        }
        $field = \Phpcmf\Service::M()->db->table('field')->where('disabled', 0)
            ->whereIn('relatedname', $like)->orderBy('displayorder ASC, id ASC')->get()->getResultArray();


        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '栏目模型字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'mid' => $mid,
            'my' => $module[$mid],
            'field' => $field,
            'module' => $module,
        ]);
        \Phpcmf\Service::V()->display('categorydata.html');
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
        $field = \Phpcmf\Service::M()->db->table('field')->where('id', $fid)->get()->getRowArray();
        if (!$field) {
            exit('字段['.$fid.']不存在');
        }
        $field['setting'] = dr_string2array($field['setting']);

        switch (intval($_GET['id'])) {

            case 1:
                // show.html字段



                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'categorydata', '');



                break;

            case 2:

                //list.html
                $rt = dr_safe_filename($post['return']);
                if (!$rt) {
                    exit('必须填写返回变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'categorydata',  $rt);


                break;


        }

        $this->_json(1, $html);

    }

}

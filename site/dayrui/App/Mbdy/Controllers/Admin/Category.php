<?php namespace Phpcmf\Controllers\Admin;

class Category extends \Phpcmf\App
{

    private $mrfield = [
        'content' => [
            'name' => '栏目内容',
            'ismain' => 1,
            'fieldtype' => 'Ueditor',
            'fieldname' => 'content',
        ],
        'thumb' => [
            'name' => '栏目缩略图',
            'ismain' => 1,
            'fieldtype' => 'File',
            'fieldname' => 'thumb',
        ],
        'id' => [
            'name' => '栏目ID',
            'ismain' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'id',
        ],
        'pid' => [
            'name' => '上级栏目ID',
            'ismain' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'pid',
        ],
        'name' => [
            'name' => '栏目名称',
            'ismain' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'name',
        ],
        'dirname' => [
            'name' => '栏目目录',
            'ismain' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'dirname',
        ],
        'url' => [
            'name' => '栏目地址',
            'ismain' => 1,
            'fieldtype' => 'Url',
            'fieldname' => 'url',
        ],
        'seo' => [
            'name' => '栏目seo信息',
            'ismain' => 1,
            'fieldtype' => 'Seo',
            'fieldname' => 'setting',
        ],
        'cat_total' => [
            'name' => '栏目内容数据量',
            'ismain' => 1,
            'fieldtype' => 'Cat_total',
            'fieldname' => 'mid',
        ],
    ];

    public function index() {

        $content = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-content');

        $module = [
            '' => [
                'name' => '共享栏目',
                'dirname' => 'share',
            ],
        ];
        if ($content) {
            foreach ($content as $i => $t) {
                if (!$t['share']) {
                    $module[$i] = $t;
                }
            }
        }

        $mid = dr_safe_filename($_GET['mid']);

        if ($mid && !$module[$mid]) {
            $this->_admin_msg(0, dr_lang('模块['.$mid.']不存在'));
        }

        if (is_file(IS_USE_MODULE.'Models/Repair.php')) {
            $cc = \Phpcmf\Service::M('repair', 'module')->get_category_field(($mid ? $mid : 'share'));
            $field = dr_array22array($this->mrfield, $cc);
        } else {
            $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.($mid ? $mid : 'share'));
            $field = dr_array22array($this->mrfield, $mdata['category_field']);
        }

        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '栏目字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'mid' => $mid,
            'my' => $module[$mid],
            'field' => $field,
            'module' => $module,
        ]);
        \Phpcmf\Service::V()->display('category.html');
    }

    // 用于cms调用
    public function cms() {

        $id = intval($_GET['id']);
        $mid = dr_safe_filename($_GET['mid']);
        if (!$id) {
            $this->_admin_msg(0, dr_lang('栏目['.$id.']不存在'));
        }

        $dir = ($mid ? $mid : 'share');
        $cat = dr_cat_value($dir, $id);
        if (!$cat) {
            $this->_admin_msg(0, dr_lang('模块['.$dir.']栏目['.$id.']缓存不存在，尝试更新缓存'));
        }
        $field = \Phpcmf\Service::M()->db->table('field')
            ->where('disabled', 0)
            ->where('relatedname', 'category-'.$dir)
            ->orderBy('displayorder ASC, id ASC')->get()->getResultArray();
        $category_field = [];
        if ($field) {
            foreach ($field as $f) {
                $f['setting'] = dr_string2array($f['setting']);
                $category_field[$f['fieldname']] = $f;
            }
        }
        $field = dr_array22array($this->mrfield, $category_field);

        \Phpcmf\Service::V()->assign([
            'id' => $id,
            'mid' => $mid,
            'cat' => $cat,
            'field' => $field,
        ]);
        \Phpcmf\Service::V()->display('category_cms.html');exit;
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
        $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.($mid ? $mid : 'share'));

        $field = \Phpcmf\Service::M()->db->table('field')
            ->where('disabled', 0)
            ->where('relatedname', 'category-'.($mid ? $mid : 'share'))
            ->orderBy('displayorder ASC, id ASC')->get()->getResultArray();
        $category_field = [];
        if ($field) {
            foreach ($field as $f) {
                $f['setting'] = dr_string2array($f['setting']);
                $category_field[$f['fieldname']] = $f;
            }
        }

        $mdata['category_field'] = dr_array22array($this->mrfield, $category_field);

        $field = $mdata['category_field'][$fid];
        if (!$field) {
            exit('字段['.$fid.']不存在');
        }

        switch (intval($_GET['id'])) {

            case 1:
                // show.html字段
                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'category', 'cat');

                break;

            case 11:
                // show.html字段
                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'category', 'top');

                break;

            case 111:
                // show.html字段
                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'category', 'parent');

                break;

            case 2:

                //list.html
                $rt = dr_safe_filename($post['return']);
                if (!$rt) {
                    exit('必须填写返回变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'category',  $rt);


                break;

            case 3:

                //list.html
                $rt = ($post['id']);
                if (!$rt) {
                    exit('必须填写ID变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_category_field_code($field, $mid, $rt);

                break;

            case 4:

                //list.html
                $rt = ($post['id']);
                if (!$rt) {
                    exit('必须填写return变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_category_list_code($field, $mid, $rt);


                break;

            case 9:

                //list.html
                $rt = ($post['id']);
                if (!$rt) {
                    exit('必须填写return变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_category_list_code($field, $mid, $rt);


                break;


        }

        $this->_json(1, $html);

    }

}

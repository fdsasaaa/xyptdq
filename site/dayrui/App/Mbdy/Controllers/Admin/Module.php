<?php namespace Phpcmf\Controllers\Admin;

class Module extends \Phpcmf\App
{
    private function get_field($field, $mid = '') {
        // 默认字段
        $field['keywords_kws'] = [
            'name' => dr_lang('关键词搜索'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Kws',
            'fieldname' => 'keywords',
        ];
        $field['keywords_tag'] = [
            'name' => dr_lang('关键词Tag插件'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Tags',
            'fieldname' => 'keywords',
        ];
        $field['inputtime'] = [
            'name' => dr_lang('录入时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'inputtime',
        ];
        $field['updatetime'] = [
            'name' => dr_lang('更新时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'updatetime',
        ];
        $field['catid'] = [
            'name' => dr_lang('栏目信息'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Catid',
            'fieldname' => 'catid',
        ];
        $field['uid'] = [
            'name' => dr_lang('账号'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Uid',
            'fieldname' => 'uid',
        ];
        $field['url'] = [
            'name' => dr_lang('内容地址'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Url',
            'fieldname' => 'url',
        ];
        $field['hits'] = [
            'name' => dr_lang('浏览次数'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Hits',
            'fieldname' => 'hits',
        ];
        if ($mid) {
            $table = \Phpcmf\Service::M()->dbprefix(SITE_ID.'_'.$mid);
            $list = \Phpcmf\Service::M()->db->query('SHOW FULL COLUMNS FROM `'.$table.'`')->getResultArray();
            if ($list) {
                foreach ($list as $t) {
                    if (!isset($field[$t['Field']])) {
                        $field[$t['Field']] = [
                            'name' => $t['Comment'] ? $t['Comment'] : $t['Field'],
                            'ismain' => 1,
                            'ismember' => 1,
                            'fieldtype' => 'Text',
                            'fieldname' => $t['Field'],
                        ];
                    }
                }
            }
        }

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

        $field = $this->get_field($mdata['field'], $mid);


        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '模块字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'mid' => $mid,
            'my' => $module[$mid],
            'field' => $field,
            'module' => $module,
        ]);
        \Phpcmf\Service::V()->display('module.html');
    }

    public function show() {

        $id = intval($_GET['id']);
        $mid = dr_safe_filename($_GET['mid']);
        $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$mid);

        if ($mdata['category_data_field']) {
            foreach ($mdata['category_data_field'] as $f) {
                $f['name'] = '栏目模型字段-'.$f['name'];
                $mdata['field'][$f['fieldname']] = $f;
            }
        }

        $field = $this->get_field($mdata['field'], $mid);
        \Phpcmf\Service::V()->assign([
            'id' => $id,
            'mid' => $mid,
            'field' => $field,
            'show_code' => '{content module='.$mid.' id='.$id.' return=cc}
标题：{$cc.title} 地址：{$cc.url}
内容：{$cc.content}
描述：{$cc.description}  截取20字 {dr_strcut($cc.description, 20)}
缩略图： {dr_thumb($cc.thumb, 200, 200)} 判断有无缩略图：{if $cc.thumb}有的{else}没有{/if}
时间：{$cc.updatetime} 自定义时间：{dr_date($cc._updatetime, \'Y-m-d\')}

=====其他字段调用方式：请点击上方《 循环时的字段 》，指定return值为：cc	
 {/content}           
            '
        ]);
        \Phpcmf\Service::V()->display('module_cms.html');exit;
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
        $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$mid);

        if ($mdata['category_data_field']) {
            foreach ($mdata['category_data_field'] as $f) {
                $f['name'] = '栏目模型字段-'.$f['name'];
                $mdata['field'][$f['fieldname']] = $f;
            }
        }
        $mdata['field'] = $this->get_field($mdata['field'], $mid);

        define('MOD_DIR', $mid);
        $field = $mdata['field'][$fid];
        if (!$field) {
            exit('字段['.$fid.']不存在');
        }

        switch (intval($_GET['id'])) {

            case 1:
                // show.html字段



                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'module', '');



                break;

            case 2:

                //list.html
                $rt = dr_safe_filename($post['return']);
                if (!$rt) {
                    exit('必须填写返回变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'module',  $rt);


                break;


        }

        $this->_json(1, $html);

    }

}

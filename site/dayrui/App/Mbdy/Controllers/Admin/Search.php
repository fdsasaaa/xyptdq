<?php namespace Phpcmf\Controllers\Admin;

class Search extends \Phpcmf\App
{

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

        $field = '<select class="form-control" name="field">';
        $fields = $this->_module_field($mdata['field'], $mdata['category_data_field']);
        foreach ($fields as $t) {
            $field.= '<option value="'.$t['fieldname'].'">'.$t['name'].'（'.$t['fieldname'].'）</option>';
        }
        $field.= '</select>';

        $sfield = '<select class="form-control" name="field">';
        $fields = $this->_search_field();
        foreach ($fields as $t) {
            $sfield.= '<option value="'.$t['fieldname'].'">'.$t['name'].'（'.$t['fieldname'].'）</option>';
        }
        foreach ($mdata['field'] as $t) {
            if (!is_file(dr_get_app_dir('mbdy').'/Models/Search/'.$t['fieldtype'].'.php')) {
                continue;
            }
            $sfield.= '<option value="'.$t['fieldname'].'">'.$t['name'].'（'.$t['fieldname'].'）</option>';
        }
        foreach ($mdata['category_data_field'] as $t) {
            if (!is_file(dr_get_app_dir('mbdy').'/Models/Search/'.$t['fieldtype'].'.php')) {
                continue;
            }
            $sfield.= '<option value="'.$t['fieldname'].'">'.$t['name'].'（'.$t['fieldname'].'）</option>';
        }
        $sfield.= '</select>';


        $afield = '<select class="form-control" name="field">';
        $table = \Phpcmf\Service::M()->dbprefix(SITE_ID.'_'.$mid);
        $list = \Phpcmf\Service::M()->db->query('SHOW FULL COLUMNS FROM `'.$table.'`')->getResultArray();
        if ($list) {
            foreach ($list as $t) {
                $afield.= '<option value="'.$t['Field'].'">'.$t['Field'].'（'.($t['Comment'] ? $t['Comment'] : $t['Field']).'）</option>';
            }
        }
        $afield.= '</select>';
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '内容搜索条件' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'mid' => $mid,
            'my' => $mdata,
            'field' => $field,
            'afield' => $afield,
            'sfield' => $sfield,
            'module' => $module,
        ]);
        \Phpcmf\Service::V()->display('search.html');
    }

    public function tag() {

        $html = '';
        $post = \Phpcmf\Service::L('input')->xss_clean($_POST);
        if (!$post) {
            $this->_json(0, '字段参数没过来');
        }

        $fid = dr_safe_filename($post['field']);
        if (!$fid) {
            $this->_json(0, '字段参数没过来');
        }

        if (intval($_GET['id']) == 2) {

            if (isset($post['order']) && $post['order']) {
                $fid.='_asc';
            }
            $html = '<a href="{Router::search_url($params, \'order\', \''.$fid.'\')}" class="{if $params.order==\''.$fid.'\'}高亮选中{/if}"> 点击排序 </a>';

            $this->_json(1, trim($html));
            exit;
        } elseif (intval($_GET['id']) == 3) {

            $html = '
<!--手动获取参数写法-->
{if $params.order}
<a href="{Router::search_url($params, \'order\', NULL)}">排序：{$params[\'order\']} </a>
{/if}
<!--自动获取小部分的搜索数组写法-->
{loop $param_value $p $v}
<a href="{Router::search_url($params, $p, NULL)}">{$v.name}：{$v.value}</a>
{/loop}            
            
            ';

            $this->_json(1, trim($html));
            exit;
        }


        $mid = dr_safe_filename($_GET['mid']);
        $mdata = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$mid);
        $mdata['field'] = $this->_search_field($mdata['field']);
        if (isset($mdata['field'][$fid])) {
            $field = $mdata['field'][$fid];
            $code = '-----搜索标签参数是固定写法不可增减，pagesize参数是控制每页显示数（可以修改），more=1表示显示栏目模型字段------
{search module=MOD_DIR id=$searchid total=$sototal order=$params.order more=1 catid=$catid page=1 pagesize=5 urlrule=$urlrule return=rs}
当前行数(从1开始)：{$key_rs+1} 当前行数(从0开始)：{$key_rs}
标题：{$rs.title} 地址：{$rs.url}
缩略图： {dr_thumb($rs.thumb, 200, 200)} 判断有无缩略图：{if $rs.thumb}有的{else}没有{/if}
时间：{$rs.updatetime} 自定义时间：{dr_date($rs._updatetime, \'Y-m-d\')}
所属栏目；{dr_cat_value($rs.catid, \'name\')} 栏目地址：{dr_cat_value($rs.catid, \'url\')}
=====其他字段调用方式 点击下方按钮生成
{/search}
分页：{$pages_rs}
调试排错诊断信息：{$debug_rs} （开发者模式下才可用）            
            ';
        } elseif (isset($mdata['category_data_field'][$fid])) {
            $field = $mdata['category_data_field'][$fid];
            $code = '-----搜索标签参数是固定写法不可增减，pagesize参数是控制每页显示数（可以修改）------
{search module=MOD_DIR id=$searchid total=$sototal order=$params.order catid=$catid page=1 pagesize=5 urlrule=$urlrule return=rs}
当前行数(从1开始)：{$key_rs+1} 当前行数(从0开始)：{$key_rs}
标题：{$rs.title} 地址：{$rs.url}
缩略图： {dr_thumb($rs.thumb, 200, 200)} 判断有无缩略图：{if $rs.thumb}有的{else}没有{/if}
时间：{$rs.updatetime} 自定义时间：{dr_date($rs._updatetime, \'Y-m-d\')}
所属栏目；{dr_cat_value($rs.catid, \'name\')} 栏目地址：{dr_cat_value($rs.catid, \'url\')}
=====其他字段调用方式 点击下方按钮生成
{/search}
分页：{$pages_rs}
调试排错诊断信息：{$debug_rs} （开发者模式下才可用）            
            ';
        } else {
            $this->_json(0, '字段不存在');
        }

        $file = dr_get_app_dir('mbdy').'/Models/Search/'.$field['fieldtype'].'.php';
        if (!is_file($file)) {
            $this->_json(0, '没有找到此字段类型['.$field['fieldtype'].']的调用方式');
        }

        require $file;

        $this->_json(1, trim($html), $code);

    }

    private function _search_field($mfield = [], $catfield = []) {
        // 默认字段
        $field = [];
        $field['keyword'] = [
            'name' => dr_lang('搜索词'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Keyword',
            'fieldname' => 'keyword',
        ];
        $field['updatetime'] = [
            'name' => dr_lang('更新时间范围'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'updatetime',
        ];
        $field['inputtime'] = [
            'name' => dr_lang('发布时间范围'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'inputtime',
        ];
        $field['catid'] = [
            'name' => dr_lang('栏目分类'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Scat',
            'fieldname' => 'catid',
        ];
        return $field + $mfield + (array)$catfield;
    }
    private function _module_field($field, $catfield) {
        // 默认字段
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
            'fieldtype' => 'Text',
            'fieldname' => 'url',
        ];
        $field['hits'] = [
            'name' => dr_lang('浏览次数'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'hits',
        ];
        return $field + (array)$catfield;
    }

}

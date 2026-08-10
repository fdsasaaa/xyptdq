<?php namespace Phpcmf\Library\Module;
/**
 * {{www.xunruicms.com}}
 * {{迅睿内容管理框架系统}}
 * 本代码基于MIT开源协议，协议规定此处版权信息不可去除
 * 本文件是框架系统文件，二次开发时不可以修改本文件，可以通过继承类方法来重写此文件
 **/

class Category {

    protected $ismain = 0;
    protected $siteid = 0;

    public function ismain($v) {
        $this->ismain = $v;
        return $this;
    }

    public function site($v) {
        $this->siteid = $v;
        return $this;
    }

    public function select($mid, $id = '', $str = '', $default = ' -- ', $onlysub = 0, $is_push = 0, $is_first = 0) {
        $siteid = $this->siteid ? $this->siteid : SITE_ID;
		$select = \Phpcmf\Service::L('Tree')->ismain($this->ismain)->select_category($this->get_category($mid, $siteid), $id, $str, $default, $onlysub, $is_push, $is_first);
        $this->siteid = 0;
        return $select;
    }

    // 获取全部栏目
    public function get_category($mid, $siteid = SITE_ID) {
        return \Phpcmf\Service::C()->get_cache('module-'.$siteid.'-'.$mid, 'category');
    }

    // 获取栏目自定义字段
    public function get_category_field($cdir) {

        $category_field = [];

        $field = $this->db->table('field')
            ->where('disabled', 0)
            ->where('relatedname', 'category-'.$cdir)
            ->orderBy('displayorder ASC, id ASC')->get()->getResultArray();
        if ($field) {
            foreach ($field as $f) {
                $f['setting'] = dr_string2array($f['setting']);
                $category_field[$f['fieldname']] = $f;
            }
        }

        return $category_field;
    }

    // 获取下级子栏目
    public function get_child($mid, $catid, $siteid = SITE_ID) {

        $cats = \Phpcmf\Service::C()->get_cache('module-'.$siteid.'-'.$mid, 'category');
        if (!$cats) {
            return [];
        }

        $rt = [];
        foreach ($cats as $c) {
            if ($c['pid'] == $catid) {
                $rt[] = $c['id'];
            }
        }

        return $rt;
    }

    // 通过目录找id
    public function get_catid($mid, $dir, $siteid = SITE_ID) {

        $cats = \Phpcmf\Service::C()->get_cache('module-'.$siteid.'-'.$mid, 'category_dir');
        if (!$cats) {
            return [];
        }

        return isset($cats[$dir]) ? $cats[$dir] : 0;
    }

    // 查询所属主栏目
    public function get_ismain_id($mid, $cat) {

        return $cat['id'];
    }

}
<?php namespace Phpcmf\Controllers\Admin;

class Categoryshow extends \Phpcmf\App
{

    public function index() {
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '栏目循环时的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
        ]);
        \Phpcmf\Service::V()->display('categoryshow.html');
    }


    public function cms() {

        $mid = dr_safe_filename($_GET['mid']);
        $module = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-content');
        if (!$module) {
            $this->_admin_msg(0, dr_lang('系统没有安装内容模块'));
        }

        \Phpcmf\Service::V()->assign([
            'mid' => $mid,
            'catid' => intval($_GET['catid']),
            'share' => $mid ? ($module[$mid]['share'] ? 1 : 0) : 1,
        ]);
        \Phpcmf\Service::V()->display('categoryshow_cms.html');
    }

    public function tag() {

        $html = '';
        $post = \Phpcmf\Service::L('input')->xss_clean($_POST);
        if (!$post) {
            exit('字段参数没过来');
        }

        switch (intval($_GET['id'])) {

            case 1:
                // 共享栏目循环

                $html.= '{category module=share';
                if (strlen($post['pid'])) {
                    $html.= ' pid='.trim($post['pid']);
                }
                if ($post['id']) {
                    $html.= ' id='.$post['id'];
                }
                if ($post['num']) {
                    $html.= ' num='.$post['num'];
                }
                if (!$post['return'] || $post['return'] == 't') {
                    $html.= '}';
                } else {
                    $html.= ' return='.$post['return'].'}';
                }
                $html.= PHP_EOL.'<br>';
                $html.= PHP_EOL.'<br>栏目名称：{$'.$post['return'].'.name}';
                $html.= PHP_EOL.'<br>栏目url：{$'.$post['return'].'.url}';
                $html.= PHP_EOL.'<br>栏目内容编辑器的值：{$'.$post['return'].'.content}';
                $html.= PHP_EOL.'<br>栏目缩略图：{dr_thumb($'.$post['return'].'.thumb)}';
                // 自定义字段
                $html.= PHP_EOL.'<br>';
                $html.= PHP_EOL.'<br>其他自定义字段参考：';
                $html.= PHP_EOL.'https://www.xunruicms.com/doc/code/field.html?--'.$post['return'];
                $html.= PHP_EOL.'<br>';
                $html.= PHP_EOL.'{/category}';


                break;

            case 2:
                // 独立模块栏目循环

                $html.= '{category ';
                if ($post['module']) {
                    $html.= ' module='.($post['module']);
                } else {
                    $this->_json(0, '必须选择一个模块');
                }
                if (strlen($post['pid'])) {
                    $html.= ' pid='.trim($post['pid']);
                }
                if ($post['id']) {
                    $html.= ' id='.$post['id'];
                }
                if ($post['num']) {
                    $html.= ' num='.$post['num'];
                }
                if (!$post['return'] || $post['return'] == 't') {
                    $html.= '}';
                } else {
                    $html.= ' return='.$post['return'].'}';
                }
                $html.= PHP_EOL.'<br>';
                $html.= PHP_EOL.'<br>栏目名称：{$'.$post['return'].'.name}';
                $html.= PHP_EOL.'<br>栏目url：{$'.$post['return'].'.url}';
                $html.= PHP_EOL.'<br>栏目内容编辑器的值：{$'.$post['return'].'.content}';
                $html.= PHP_EOL.'<br>栏目缩略图：{dr_thumb($'.$post['return'].'.thumb)}';
                // 自定义字段
                $html.= PHP_EOL.'<br>';
                $html.= PHP_EOL.'<br>其他自定义字段参考：';
                $html.= PHP_EOL.'https://www.xunruicms.com/doc/code/field.html?--'.$post['return'];
                $html.= PHP_EOL.'<br>';
                $html.= PHP_EOL.'{/category}';


                break;


        }

        $this->_json(1, $html);

    }

}

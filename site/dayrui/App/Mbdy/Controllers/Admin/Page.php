<?php namespace Phpcmf\Controllers\Admin;

class Page extends \Phpcmf\App
{


    public function index() {
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '页面标签调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'list' => [
                [
                    'name' => '全局页面',
                    'help' => '465',
                    'msg' => '任何模板页面通用的',
                ],
                [
                    'name' => '网站首页',
                    'help' => '115',
                    'msg' => '网站首页的模板文件，一般是index.html',
                ],
                [
                    'name' => '模块栏目列表页面',
                    'help' => '118',
                    'msg' => '共享栏目或者模块栏目的列表页面，一般是category.html，list.html',
                ],
                [
                    'name' => '模块内容页面',
                    'help' => '126',
                    'msg' => '模块内容详情页面，一般是show.html',
                ],
                [
                    'name' => '模块内容搜索页面',
                    'help' => '127',
                    'msg' => '模块内容搜索、筛选列表页面，一般是search.html',
                ],
                [
                    'name' => '共享栏目单页面',
                    'help' => '117',
                    'msg' => '栏目的单页类型模板，一般是关于我们等类似页面，一般是page.html',
                ],
            ],
        ]);
        \Phpcmf\Service::V()->display('index.html');
    }


    public function qj_index() {

    }

}

<?php namespace Phpcmf\Admin;
/**
 * {{www.xunruicms.com}}
 * {{迅睿内容管理框架系统}}
 * 本文件是框架系统文件，二次开发时不可以修改本文件，可以通过继承类方法来重写此文件
 **/

// 文件操作控制器
class Devfile extends \Phpcmf\Common {

    public $root_path;

    public function index() {

        $menu = [];
        if (is_file($this->root_path.'menu.php')) {
            $menu = require $this->root_path.'menu.php';
        }

        $pc = strpos($this->root_path, '/pc/') ? 1 : 0;

        \Phpcmf\Service::V()->assign([
            'url' => $pc ? '/index.php' : str_replace(SITE_MURL, '/', SITE_URL),
            'demo' => $pc ? 'pc' : 'mobile',
            'prefix' => 'tpl/dev_'.($pc ? 'pc' : 'mobile'),
            'devmenu' => $menu,
        ]);
        \Phpcmf\Service::V()->display('dev.html');exit;
    }

    public function edit() {

        list($at, $p) = explode(':', dr_safe_replace($_GET['at']));
        $file = APPPATH.'Action/'.ucfirst($at).'.php';
        if (is_file($file)) {
            require $file;
        } else {
            $file = $this->root_path.'action/'.$at.'.php';
            if (is_file($file)) {
                require $file;
            } else {
                $file = $this->root_path.'html/'.$at.'.html';
                if (is_file($file)) {
                    require \Phpcmf\Service::V()->code2php(file_get_contents($file));
                    exit;
                }
                $this->_json(0, '执行文件（'.(IS_DEV ? $file : $at).'）不存在');
            }
        }
    }

}

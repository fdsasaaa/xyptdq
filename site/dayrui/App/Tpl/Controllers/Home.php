<?php namespace Phpcmf\Controllers;

class Home extends \Phpcmf\App
{

    public function page() {
        $data = \Phpcmf\Service::M()->table_site('share_category')->where('tid=0')->order_by('id desc')->getRow();
        if (!$data) {
            $this->_admin_msg(0, '当前系统没有创建单网页');
        }
        dr_redirect('index.php?c=category&id='.$data['id']);
    }

    public function category() {
        $data = \Phpcmf\Service::M()->table_site('share_category')->where('tid=1 and mid<>""')->order_by('id desc')->getRow();
        if (!$data) {
            $this->_admin_msg(0, '当前系统没有创建模块栏目');
        }
        dr_redirect('index.php?c=category&id='.$data['id']);
    }

    public function show() {
        $data = \Phpcmf\Service::M()->table_site('share_category')->where('tid=1 and mid<>""')->order_by('id desc')->getRow();
        if (!$data) {
            $this->_admin_msg(0, '当前系统没有创建模块栏目');
        }
        $mid = $data['mid'];
        $data = \Phpcmf\Service::M()->table_site($mid)->order_by('id desc')->getRow();
        if (!$data) {
            $this->_admin_msg(0, '没有录入可用内容');
        }
        dr_redirect('index.php?c=show&id='.$data['id']);
    }

    public function search() {
        $data = \Phpcmf\Service::M()->table_site('share_category')->where('tid=1 and mid<>""')->order_by('id desc')->getRow();
        if (!$data) {
            $this->_admin_msg(0, '当前系统没有创建模块栏目');
        }
        dr_redirect('index.php?c=search&s='.$data['mid']);
    }

}

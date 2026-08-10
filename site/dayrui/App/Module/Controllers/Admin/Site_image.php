<?php namespace Phpcmf\Controllers\Admin;

require CMSPATH.'Control/Admin/Site_image.php';

class Site_image extends \Phpcmf\Common
{

    public function index() {

        $obj = new \Phpcmf\Control\Admin\Site_image();
        $obj->index();
    }


}

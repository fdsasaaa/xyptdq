<?php namespace Phpcmf\Controllers\Admin;

class Dev_mobile extends \Phpcmf\Admin\Devfile
{

    public function __construct()
    {
        parent::__construct();
        $this->root_path = TPLPATH.'mobile/'.SITE_TEMPLATE.'/dev/';
    }

}

<?php namespace Phpcmf\Controllers\Admin;

class Dev_pc extends \Phpcmf\Admin\Devfile
{

    public function __construct()
    {
        parent::__construct();
        $this->root_path = TPLPATH.'pc/'.SITE_TEMPLATE.'/dev/';
    }

}

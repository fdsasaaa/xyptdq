<?php namespace Phpcmf\Controllers\Admin;

class Tpl_pc extends \Phpcmf\Admin\File
{

    public function __construct()
    {
        parent::__construct();
        $this->root_path = TPLPATH.'pc/';
        $this->backups_dir = 'template';
        $this->backups_path = WRITEPATH.'backups/'.$this->backups_dir.'/';
    }

    public function index() {
        $this->_List();
    }

    public function edit() {
        $this->_Edit();
    }

    public function add() {
        $this->_Add();
    }

    public function clear_del() {
        $this->_Clear();
    }

    public function del() {
        $this->_Del();
    }

    public function image_index() {
        $this->_Image();
    }


}

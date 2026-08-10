<?php namespace Phpcmf\Controllers\Admin;

/**
 * 二次开发时可以修改本文件，不影响升级覆盖
 */

class Verify extends \Phpcmf\Admin\Module
{

	public function index() {
		$this->_Admin_Verify_List();
	}

	public function s9_index() {
		$_GET['status'] = 9;
		$this->_Admin_Verify_List();
	}

	public function s1_index() {
		$_GET['status'] = 1;
		$this->_Admin_Verify_List();
	}

	public function s2_index() {
		$_GET['status'] = 2;
		$this->_Admin_Verify_List();
	}

	public function s3_index() {
		$_GET['status'] = 3;
		$this->_Admin_Verify_List();
	}

	public function s4_index() {
		$_GET['status'] = 4;
		$this->_Admin_Verify_List();
	}

	public function edit() {
		$this->_Admin_Verify_Edit();
	}

	public function del() {
		$this->_Admin_Verify_Del();
	}
}

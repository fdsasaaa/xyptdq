<?php namespace Phpcmf\Controllers\Admin;


class Api extends \Phpcmf\Common
{


    // 查看流程
    public function verify() {

        $id = intval(\Phpcmf\Service::L('input')->get('id'));
        if (!$id) {
            $this->_json(0, dr_lang('审核流程id不存在'));
        }

        $data = \Phpcmf\Service::M()->db->table('admin_verify')->where('id', $id)->get()->getRowArray();
        if (!$data) {
            $this->_json(0, dr_lang('数据#%s不存在', $id));
        }

        \Phpcmf\Service::V()->assign([
            'role' => \Phpcmf\Service::M('Auth')->get_role_all(),
            'value' => dr_string2array($data['verify']),
        ]);
        \Phpcmf\Service::V()->display('verify_show.html');exit;
    }

}

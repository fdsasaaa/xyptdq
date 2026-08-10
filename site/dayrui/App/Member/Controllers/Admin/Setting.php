<?php namespace Phpcmf\Controllers\Admin;


class Setting extends \Phpcmf\Common
{

    public function index() {

        $page = intval(\Phpcmf\Service::L('input')->get('page'));

        // 获取会员全部配置信息
        $data = [];
        $result = \Phpcmf\Service::M()->db->table('member_setting')->get()->getResultArray();
        if ($result) {
            foreach ($result as $t) {
                $data[$t['name']] = dr_string2array($t['value']);
            }
        }

        if (IS_AJAX_POST) {
            $save = ['register', 'login', 'oauth', 'config', 'list_field'];
            $post = \Phpcmf\Service::L('input')->post('data');
            if ($post['register']['sms']) {
                if (!dr_in_array('phone', $post['register']['field'])) {
                    $this->_json(0, dr_lang('短信验证注册必须让手机号作为注册字段'));
                } elseif (!$post['register']['code'] && !SYS_SMS_IMG_CODE) {
                    $this->_json(0, dr_lang('短信验证注册必须开启图片验证码'));
                }
            }
            if ($post['list_field']) {
                foreach ($post['list_field'] as $t) {
                    if ($t['func']) {
                        if (method_exists(\Phpcmf\Service::L('Function_list'), $t['func'])) {
                        } elseif (!function_exists($t['func'])) {
                            $this->_json(0, dr_lang('列表回调函数[%s]未定义', $t['func']));
                        } elseif (strpos($t['func'], 'dr_') === false && strpos($t['func'], 'my_') === false) {
                            $this->_json(0, '函数【'.$t['func'].'】必须以dr_或者my_开头');
                        }
                    }
                }
            }
            foreach ($save as $name) {
                $row = \Phpcmf\Service::M()->table('member_setting')->where('name', $name)->getRow();
                if ($row) {
                    \Phpcmf\Service::M()->db->table('member_setting')->where('name', $name)->update([
                        'name' => $name,
                        'value' => dr_array2string($post[$name])
                    ]);
                } else {
                    \Phpcmf\Service::M()->db->table('member_setting')->replace([
                        'name' => $name,
                        'value' => dr_array2string($post[$name])
                    ]);
                }
            }
            \Phpcmf\Service::M('cache')->sync_cache('member'); // 自动更新缓存
            $this->_json(1, dr_lang('操作成功'));
        }

        if (!$data['list_field']) {
            $data['list_field'] = $this->member_cache['list_field'];
        }

        // 主表字段
        $field = \Phpcmf\Service::M()->db->table('field')
            ->where('disabled', 0)
            ->where('ismain', 1)
            ->where('relatedname', 'member')
            ->orderBy('displayorder ASC,id ASC')
            ->get()->getResultArray();
        $field = dr_list_field_value($data['list_field'], \Phpcmf\Service::L('Field')->member_list_field(), $field);

        \Phpcmf\Service::V()->assign([
            'data' => $data,
            'page' => $page,
            'form' => dr_form_hidden(['page' => $page]),
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '用户设置' => ['member/setting/index', 'fa fa-cog'],
                    'help' => [1042],
                ]
            ),
            'field' => $field,
            'oauth' => dr_oauth_list(),
            'group' => \Phpcmf\Service::M()->table('member_group')->getAll(),
            'synurl' => \Phpcmf\Service::M('member')->get_sso_url(),
        ]);
        \Phpcmf\Service::V()->display('member_setting.html');
    }


}

<?php namespace Phpcmf\Controllers\Admin;

class Member extends \Phpcmf\App
{

    private function get_field() {


        $field = $this->member_cache['field'];
        // 默认字段
        $field['regtime'] = [
            'name' => dr_lang('注册时间'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Date',
            'fieldname' => 'regtime',
        ];
        $field['username'] = [
            'name' => dr_lang('用户名'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'username',
        ];
        $field['email'] = [
            'name' => dr_lang('邮箱'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'email',
        ];
        $field['phone'] = [
            'name' => dr_lang('手机号'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'phone',
        ];
        $field['score'] = [
            'name' => SITE_SCORE,
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'score',
        ];
        $field['name'] = [
            'name' => dr_lang('姓名'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Text',
            'fieldname' => 'name',
        ];
        $field['money'] = [
            'name' => dr_lang('可用的余额'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Pay',
            'fieldname' => 'money',
        ];
        $field['freeze'] = [
            'name' => dr_lang('冻结的rmb'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Pay',
            'fieldname' => 'freeze',
        ];
        $field['spend'] = [
            'name' => dr_lang('累计消费'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Pay',
            'fieldname' => 'spend',
        ];
        $field['group'] = [
            'name' => dr_lang('所属用户组'),
            'ismain' => 1,
            'ismember' => 1,
            'fieldtype' => 'Member_group',
            'fieldname' => 'group',
        ];
        return $field;
    }

    public function index() {

        $field = $this->get_field();
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '会员信息字段的模板调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'field' => $field,
            'return' => dr_safe_filename($_GET['return']),
        ]);
        \Phpcmf\Service::V()->display('member.html');
    }

    public function tag() {

        $html = '';
        $post = \Phpcmf\Service::L('input')->xss_clean($_POST);
        if (!$post) {
            exit('字段参数没过来');
        }
        $fid = dr_safe_filename($post['field']);
        if (!$fid) {
            exit('字段参数没过来');
        }

        $field = $this->get_field();

        $field = $field[$fid];
        if (!$field) {
            exit('字段['.$fid.']不存在');
        }

        switch (intval($_GET['id'])) {

            case 1:
                // show.html字段



                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'form', '');



                break;

            case 2:

                //list.html
                $rt = dr_safe_filename($post['return']);
                if (!$rt) {
                    exit('必须填写返回变量');
                }

                $html = \Phpcmf\Service::M('code', APP_DIR)->get_field_code($field, 'member',  $rt);


                break;


        }

        $this->_json(1, $html);

    }

}

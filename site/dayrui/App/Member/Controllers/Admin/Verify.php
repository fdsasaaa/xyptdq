<?php namespace Phpcmf\Controllers\Admin;


// 审核管理
class Verify extends \Phpcmf\Table
{

    private $group;

    public function __construct()
    {
        parent::__construct();

        $this->my_field = array(
            'username' => array(
                'ismain' => 1,
                'name' => dr_lang('账号'),
                'fieldname' => 'username',
                'fieldtype' => 'Text',
                'setting' => array(
                    'option' => array(
                        'width' => 200,
                    ),
                    'validate' => array(
                        'required' => 1,
                    )
                )
            ),
            'email' => array(
                'ismain' => 1,
                'name' => dr_lang('邮箱'),
                'fieldname' => 'email',
                'fieldtype' => 'Text',
                'setting' => array(
                    'option' => array(
                        'width' => 200,
                    ),
                    'validate' => array(
                        'required' => 1,
                    )
                )
            ),
            'phone' => array(
                'ismain' => 1,
                'name' => dr_lang('手机'),
                'fieldname' => 'phone',
                'fieldtype' => 'Text',
                'setting' => array(
                    'option' => array(
                        'width' => 200,
                    ),
                    'validate' => array(
                        'required' => 1,
                    )
                )
            ),
            'name' => array(
                'ismain' => 1,
                'name' => dr_lang('姓名'),
                'fieldname' => 'name',
                'fieldtype' => 'Text',
                'setting' => array(
                    'option' => array(
                        'width' => 200,
                    ),
                    'validate' => array(
                        'required' => 1,
                    )
                )
            ),
        );
        // 表单显示名称
        $this->name = dr_lang('用户');
        // 初始化数据表
        if ($this->member_cache['field']) {
            foreach ($this->member_cache['field'] as $i => $t) {
                $this->member_cache['field'][$i]['setting']['validate']['required'] = 0;
                $this->my_field[$t['fieldname']] = $t;
            }
        }
        if (!isset($this->member_cache['list_field']) || !$this->member_cache['list_field']) {
            $this->member_cache = \Phpcmf\Service::M('member', 'member')->cache();
        }
        // 初始化数据表
        $list_field = [
            'avatar' => array(
                'use' => '1',
                'name' => '头像',
                'width' => '70',
                'func' => 'dr_member_list_avatar',
                'center' => '1',
            ),
        ];
        $this->_init([
            'table' => 'member',
            'stable' => 'member_data',
            'field' => $this->member_cache['field'],
            'join_list' => ['member_data', 'member.id=member_data.id', 'left'],
            'order_by' => 'member.id desc',
            'list_field' => dr_array22array($list_field, $this->member_cache['list_field']),
        ]);
        $this->group = $this->member_cache['group'];
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '待审核用户' => ['member/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-user'],
                ]
            ),
            'field' => $this->my_field,
            'group' => $this->group,
            'member_list_field' => dr_array22array(\Phpcmf\Service::L('Field')->member_list_field(), $this->member_cache['field']),
            'is_show_search_bar' => $this->member_cache['config']['is_show_search_bar'],
        ]);
    }

    // 用户管理
    public function index() {

        $p = [];
        $name = dr_safe_replace(\Phpcmf\Service::L('input')->request('field'));
        $value = dr_safe_replace(\Phpcmf\Service::L('input')->request('keyword'));

        $where = [
            \Phpcmf\Service::M()->dbprefix('member').'.`id` IN (select id from `'.\Phpcmf\Service::M()->dbprefix('member_data').'` where `is_verify`=0)',
        ];

        if ($name && $value && isset($this->my_field[$name])) {
            $p[$name] = $value;
            $where[] = '`'.$name.'` LIKE "%'.$value.'%"';
        }

        $groupid = \Phpcmf\Service::L('input')->request('groupid');
        if ($groupid && is_array($groupid)) {
            $in = [];
            foreach ($groupid as $gid) {
                $gid = intval($gid);
                if ($gid) {
                    $in[] = $gid;
                }
            }
            if ($in) {
                $where[] = \Phpcmf\Service::M()->dbprefix('member').'.id IN (select uid from `'.\Phpcmf\Service::M()->dbprefix('member_group_index').'` where gid in ('.implode(',', $in).'))';
                $p['groupid'] = $in;
            }
        }
        
        $where && \Phpcmf\Service::M()->set_where_list(implode(' AND ', $where));

        $this->field = dr_array22array(\Phpcmf\Service::L('Field')->member_list_field(), $this->my_field);
        $this->is_ajax_list = true;
        $this->_List($p);
        $this->mytable = [
            'foot_tpl' => '',
            'link_tpl' => '',
            'link_var' => 'html = html.replace(/\{id\}/g, row.id);
            html = html.replace(/\{uid\}/g, row.id);',
        ];
        $uriprefix = APP_DIR.'/'.\Phpcmf\Service::L('Router')->class;
        if ($this->_is_admin_auth('del') || $this->_is_admin_auth('edit')) {
            $this->mytable['foot_tpl'].= '<label class="table_select_all"><input onclick="dr_table_select_all(this)" type="checkbox"><span></span></label>';
        }
        if ($this->_is_admin_auth('del')) {
            $this->mytable['foot_tpl'].= '<label><button type="button" onclick="dr_ajax_option_user(\''.dr_url('member/home/del').'\', 1)" class="btn red btn-sm"> <i class="fa fa-trash"></i> '.dr_lang('删除').'</button></label>';
        }

        if ($this->_is_admin_auth('edit')) {
            $this->mytable['link_tpl'] .= '<label><a href="javascript:dr_iframe_show(\'' . dr_lang('登录记录') . '\', \'' . dr_url('member/home/login_index') . '&id={id}\', \'80%\')" class="btn btn-xs blue"> <i class="fa fa-calendar"></i> ' . dr_lang('记录') . '</a></label>';
            $this->mytable['foot_tpl'] .= '
             <label><button type="button" onclick="dr_ajax_option(\''.dr_url('member/verify/edit').'\', \''.dr_lang('你确定要通过审核吗？').'\', 1)" class="btn blue btn-sm"> <i class="fa fa-check-square-o"></i> '.dr_lang('通过').'</button></label>
            ';
        }

        \Phpcmf\Service::V()->assign([
            'mytable' => $this->mytable,
            'is_verify' => 1,
            'uriprefix' => 'member/home',
        ]);
        \Phpcmf\Service::V()->display('member_list.html');
    }

    // 审核
    public function edit() {

        $ids = \Phpcmf\Service::L('input')->get_post_ids();
        if (!$ids) {
            $this->_json(0, dr_lang('所选用户不存在'));
        }

        foreach ($ids as $id) {
            \Phpcmf\Service::M('member')->verify_member($id);
        }

        $this->_json(1, dr_lang('操作成功'));
    }


}

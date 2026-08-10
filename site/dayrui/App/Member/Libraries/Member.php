<?php namespace Phpcmf\Library\Member;

class Member {

    // phpcmf初始化
    public function init($ci) {

        // 开启session
        $ci->session();
        // 登录状态验证
        if (!$ci->member && !in_array(\Phpcmf\Service::L('Router')->class, ['register', 'login', 'api', 'pay'])) {
            if (APP_DIR && dr_is_module(APP_DIR)
                && \Phpcmf\Service::L('Router')->class == 'home' && \Phpcmf\Service::L('Router')->method == 'add') {
                // 游客发布权限
            } else {
                // 会话超时，请重新登录
                if (IS_API_HTTP) {
                    $ci->_json(0, dr_lang('无法获取到登录用户信息'));
                } elseif (method_exists($ci, \Phpcmf\Service::L('Router')->method)) {
                    \Phpcmf\Service::L('Router')->go_member_login(dr_now_url());
                } else {
                    $ci->goto_404_page('无法识别的控制器');
                }
            }
        }

        if ($ci->member && \Phpcmf\Service::L('Router')->class != 'api'
            && !$ci->member['regip'] && SYS_TIME - $ci->member['regtime'] > 100) {
            //补全注册ip
            $ci->member['regip'] = \Phpcmf\Service::L('input')->ip_info();
            \Phpcmf\Service::M()->table('member')->update($ci->member['id'], [
                'regip' => $ci->member['regip']
            ]);
        }

        \Phpcmf\Service::V()->assign(\Phpcmf\Service::L('Seo')->member(\Phpcmf\Service::L('cache')->get('menu-member')));
    }

    // 用户组是否过期
    public function group_timeout($ci) {
        if ($ci->member) {
            // 用户组是否过期
            if ($ci->member['group_timeout'] && dr_member_group_is_timeout()) {
                $msg = dr_lang('您的用户组（%s）于%s过期', $ci->member_cache['group'][$ci->member['group_timeout']]['name'], dr_date($ci->member['group_timeout_time']));
                $rt = \Phpcmf\Hooks::trigger_callback('member_group_timeout', $ci->member);
                if ($rt && $rt['code']) {
                    // 自定义执行段
                } else {
                    if ($ci->member_cache['group'][$ci->member['group_timeout']]['setting']['outtype'] == 2) {
                        // 跳转指定页面
                        $url = $ci->member_cache['group'][$ci->member['group_timeout']]['setting']['out_url'];
                        if (strpos(FC_NOW_URL, $url) !== false) {
                            // 表示本身页面
                        } else {
                            $ci->_msg(0, $msg, $url);
                        }
                    } elseif ($ci->member_cache['group'][$ci->member['group_timeout']]['setting']['outtype'] == 1) {
                        // 跳转续费页面
                        $ci->_msg(0, $msg, dr_member_url('apply/level', ['gid' => $ci->member['group_timeout']]));
                    }
                }
            }
            // 判断用户的权限
            if (!in_array(\Phpcmf\Service::L('Router')->class, ['register', 'login', 'api'])) {
                $this->member_option($ci);
            }
        }
    }

    /**
     * 后台登录判断
     */
    public function member_option($ci) {

        if (!IS_MEMBER) {
            return;
        }

        // 有用户组来获取最终的强制权限
        $ci->member_cache['config']['complete'] = $ci->member_cache['config']['mobile'] = $ci->member_cache['config']['avatar'] = 0;
        // 强制完善资料
        if (!$ci->member_cache['config']['complete']) {
            $ci->member_cache['config']['complete'] = (int)\Phpcmf\Service::L('member_auth', 'member')->member_auth('complete', $ci->member);
        }
        // 强制手机认证
        if (!$ci->member_cache['config']['mobile']) {
            $ci->member_cache['config']['mobile'] = (int)\Phpcmf\Service::L('member_auth', 'member')->member_auth('mobile', $ci->member);
        }
        // 强制email认证
        if (!$ci->member_cache['config']['email']) {
            $ci->member_cache['config']['email'] = (int)\Phpcmf\Service::L('member_auth', 'member')->member_auth('email', $ci->member);
        }
        // 强制头像上传
        if (!$ci->member_cache['config']['avatar']) {
            $ci->member_cache['config']['avatar'] = (int)\Phpcmf\Service::L('member_auth', 'member')->member_auth('avatar', $ci->member);
        }

        if (!$ci->member['is_verify']) {
            // 审核提醒
            $ci->_msg(0, dr_lang('账号还没有通过审核'), dr_member_url('api/verify'));
        } elseif ($ci->member_cache['config']['complete']
            && !$ci->member['is_complete']
            &&\Phpcmf\Service::L('Router')->class != 'account') {
            // 强制完善资料
            $ci->_msg(0, dr_lang('账号必须完善资料'), dr_member_url('account/index'));
        } elseif ($ci->member_cache['config']['mobile']
            && !$ci->member['is_mobile']
            &&\Phpcmf\Service::L('Router')->class != 'account') {
            // 强制手机认证
            $ci->_msg(0, dr_lang('账号必须手机认证'), dr_member_url('account/mobile'));
        } elseif ($ci->member_cache['config']['email']
            && !$ci->member['is_email']
            &&\Phpcmf\Service::L('Router')->class != 'account') {
            // 强制邮箱认证
            $ci->_msg(0, dr_lang('账号必须邮箱认证'), dr_member_url('account/email'));
        } elseif ($ci->member_cache['config']['avatar']
            && !$ci->member['is_avatar']
            &&\Phpcmf\Service::L('Router')->class != 'account') {
            // 强制头像上传
            $ci->_msg(0, dr_lang('账号必须上传头像'), dr_member_url('account/avatar'));
        }


    }



}


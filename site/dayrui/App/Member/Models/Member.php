<?php namespace Phpcmf\Model\Member;

class Member extends \Phpcmf\Model\Member
{

    /**
     * 内容发布之后
     */
    public function module_content_after($module, $data, $member) {

        // 增减金币
        $score = \Phpcmf\Service::L('member_auth', 'member')->category_auth($module, $data[1]['catid'], 'score', $member);
        $score && \Phpcmf\Service::M('member')->add_score($data[1]['uid'], $score, dr_lang('%s内容《%s》发布', $module['name'], $data[1]['title']), $data[1]['url']);
        // 增减人民币
        $money = \Phpcmf\Service::L('member_auth', 'member')->category_auth($module, $data[1]['catid'], 'money', $member);
        if ($money) {
            $rr = \Phpcmf\Service::M('member')->add_money($data[1]['uid'], $money);
            if ($rr['code']) {
                if (!dr_is_app('pay')) {
                    log_message('error', '模块【'.$module['name'].'】发布内容（'.$data[1]['id'].'）扣减人民币失败：没有安装「支付系统」插件');
                } else {
                    \Phpcmf\Service::M('Pay', 'pay')->add_paylog([
                        'uid' => $member['id'],
                        'touid' => 0,
                        'mid' => 'system',
                        'title' => dr_lang('%s内容《%s》发布', $module['name'], $data[1]['title']),
                        'value' => $money,
                        'type' => 'finecms',
                        'status' => 1,
                        'result' => dr_url_prefix($data[1]['url'], $module['dirname'], SITE_ID, ''),
                        'paytime' => SYS_TIME,
                        'inputtime' => SYS_TIME,
                    ]);
                }
            } else {
                log_message('error', '模块【'.$module['name'].'】发布内容（'.$data[1]['id'].'）扣减人民币失败：'.$rr['msg']);
            }
        }
        // 增减经验
        $exp = \Phpcmf\Service::L('member_auth', 'member')->category_auth($module, $data[1]['catid'], 'exp', $member);
        $exp && \Phpcmf\Service::M('member')->add_experience($data[1]['uid'], $exp, dr_lang('%s内容《%s》发布', $module['name'], $data[1]['title']), $data[1]['url']);
    }

    /**
     * 登录记录
     *
     * @param   intval  $data       会员
     * @param   string  $OAuth      登录方式
     */
    protected function _login_log($data, $type = '') {

        if (IS_ADMIN && APP_DIR == 'member') {
            return;// 后台创建的用户不记录登录日志
        }

        $ip = \Phpcmf\Service::L('input')->ip_address();
        if (!$ip || !$data['id']) {
            return;
        }

        // 防止多次记录
        if (\Phpcmf\Service::L('cache')->get_auth_data("member_login_after_".$data['id'], SITE_ID, 60)) {
            return;
        }

        $agent = \Phpcmf\Service::L('input')->get_user_agent();
        if (strlen($agent) <= 5) {
            return;
        }

        $log = [
            'uid' => $data['id'],
            'type' => $type,
            'loginip' => $ip,
            'logintime' => SYS_TIME,
            'useragent' => substr($agent, 0, 255),
        ];

        // 只保留20条登录记录
        $row = $this->table('member_login')->where('uid', $data['id'])
            ->order_by('logintime desc')->getAll(21);
        if (dr_count($row) > 20) {
            $ids = '';
            foreach ($row as $t) {
                $ids.= (int)$t['id'].',';
            }
            // 删除多余的记录
            $ids && $this->db->table('member_login')->where('uid', $data['id'])->where('id not in ('.trim($ids, ',').')')->delete();
        }

        // 登录后的通知
        \Phpcmf\Service::L('Notice')->send_notice('member_login', $data);

        // 登录后的钩子
        $data['log'] = [
            'now' => $log,
            'before' => $row,
        ];
        \Phpcmf\Hooks::trigger('member_login_after', $data);

        \Phpcmf\Service::L('cache')->set_auth_data("member_login_after_".$data['id'], 1, SITE_ID);

        // 同一天Ip一致时只更新一次更新时间
        if ($row = $this->db
            ->table('member_login')
            ->where('uid', $data['id'])
            ->where('loginip', $ip)
            ->where('DATEDIFF(from_unixtime(logintime),now())=0')
            ->get()
            ->getRowArray()) {
            $this->db->table('member_login')->where('id', $row['id'])->update($log);
        } else {
            $this->db->table('member_login')->insert($log);
        }

    }

    /**
     * 初始化处理
     */
    public function init_member($member) {

        // 明天凌晨时间戳
        $time = strtotime(date('Y-m-d', strtotime('+1 day')));

        // 每日登录积分处理
        if (dr_is_app('explog')) {
            $value = \Phpcmf\Service::L('member_auth', 'member')->member_auth('login_exp', $member);
            if ($value && !\Phpcmf\Service::L('input')->get_cookie('login_experience_'.$member['id'])) {
                $this->add_experience($member['id'], $value, dr_lang('每日登陆'), '', 'login_exp_'.date('Ymd', SYS_TIME), 1);
                \Phpcmf\Service::L('input')->set_cookie('login_experience_'.$member['id'], 1, $time - SYS_TIME);
            }
        }

        // 每日登录金币处理
        if (dr_is_app('scorelog')) {
            $value = \Phpcmf\Service::L('member_auth', 'member')->member_auth('login_score', $member);
            if ($value && !\Phpcmf\Service::L('input')->get_cookie('login_score_'.$member['id'])) {
                $this->add_score($member['id'], $value, dr_lang('每日登陆'), '', 'login_score_'.date('Ymd', SYS_TIME), 1);
                \Phpcmf\Service::L('input')->set_cookie('login_score_'.$member['id'], 1, $time - SYS_TIME);
            }
        }

        // 没有注册ip时，短时间内按获取的地址作为ip填充
        if (!$member['regip'] && $member['regtime']) {
            $ctime = SYS_TIME - $member['regtime'];
            if ($ctime < 80000 && $ctime > 100) {
                $this->table('member')->update($member['id'], [
                    'regip' => (string)\Phpcmf\Service::L('input')->ip_address()
                ]);
            }
        }
    }

    /**
     * 用户组信息
     */
    public function get_member_group($data) {

        if (IS_ADMIN && !$this->db->tableExists($this->dbprefix('member_group_index'))) {
            return $data;
        }

        $data2 = $this->update_group($data, $this->db->table('member_group_index')->where('uid', (int)$data['id'])->get()->getResultArray());
        if ($data2) {
            foreach ($data2 as $t) {
                $data['group_name'][$t['gid']] = $t['group_name'] = \Phpcmf\Service::C()->member_cache['group'][$t['gid']]['name'];
                $t['group_icon'] = \Phpcmf\Service::C()->member_cache['group'][$t['gid']]['level'][$t['lid']]['icon'];
                $t['group_level'] = \Phpcmf\Service::C()->member_cache['group'][$t['gid']]['level'][$t['lid']]['name'];
                $data['group'][$t['gid']] = $t;
                $data['groupid'][$t['gid']] = $t['gid'];
                $data['levelid'][$t['gid']] = $t['lid'];
                $data['authid'][] = $t['lid'] ? $t['gid'].'-'.$t['lid'] : $t['gid'];
                if ($t['timeout']) {
                    $data['group_timeout'] = $t['gid'];
                    $data['group_timeout_time'] = $t['etime'];
                }
            }
        }

        return $data;
    }

    /**
     * 授权登录信息
     */
    public function oauth($uid) {

        $data = $this->db->table('member_oauth')->where('uid', $uid)->get()->getResultArray();
        if (!$data) {
            return [];
        }

        $rt = [];
        foreach ($data as $t) {
            $rt[$t['oauth']] = $t;
        }

        return $rt;
    }

    // 获取authid
    public function authid($uid) {

        if (!$uid) {
            return [0];
        } elseif ($uid == $this->uid) {
            return \Phpcmf\Service::C()->member['authid'];
        }

        $rt = [];
        $data2 = $this->db->table('member_group_index')->where('uid', $uid)->get()->getResultArray();
        if ($data2) {
            foreach ($data2 as $t) {
                $rt[] = $t['lid'] ? $t['gid'].'-'.$t['lid'] : $t['gid'];
            }
        }

        return $rt;
    }

    // 更新用户组
    // member 用户信息
    // groups 拥有的用户组
    public function update_group($member, $groups) {

        $g = [];
        if (!$member || !$groups) {
            return $g;
        }

        $uid = (int)$member['id'];
        foreach ($groups as $group) {
            // 判断是否可用
            if (!\Phpcmf\Service::C()->member_cache['group'][$group['gid']]) {
                continue;
            }
            $group['gid'] = (int)$group['gid'];
            $group['timeout'] = 0;
            // 判断等级是否有效
            $levels = isset(\Phpcmf\Service::C()->member_cache['group'][$group['gid']]['level']) ? \Phpcmf\Service::C()->member_cache['group'][$group['gid']]['level'] : [];
            if ($levels) {
                // 当已知等级不存在时
                if ($group['lid'] && (!isset($levels[$group['lid']]) || !$levels[$group['lid']])) {
                    $this->db->table('member_group_index')->where('uid', $uid)->where('gid', $group['gid'])->update(['lid' => 0]);
                    $group['lid'] = 0;
                }
                // 没有等级时自动选取免费等级
                if (!$group['lid']) {
                    foreach ($levels as $ls) {
                        if (!$ls['value']) {
                            $group['lid'] = $ls['id'];
                            break;
                        }
                    }
                }
            } elseif ($group['lid']) {
                // 还原升级
                $this->db->table('member_group_index')->where('uid', $uid)->where('gid', $group['gid'])->update(['lid' => 0]);
                $group['lid'] = 0;
            }
            $group_info = \Phpcmf\Service::C()->member_cache['group'][$group['gid']];
            // 判断过期
            $price = floatval($group_info['price']);
            if ($group['etime'] && $group['etime'] - SYS_TIME < 0) {
                // 过期了
                if ($group_info['setting']['timeout']) {
                    // 过期自动续费price
                    $name = $group_info['unit'] ? 'score' : 'money';
                    if ($name == 'money') {
                        // 余额
                        if ($price > 0) {
                            // 收费组情况下
                            if ($member[$name] - $price < 0) {
                                // 余额不足 删除
                                if (!$group_info['setting']['outtype'] && $this->delete_group($uid, $group['gid'], 0)) {
                                    $this->notice($uid, 2, dr_lang('您的用户组（%s）已过期，自动续费失败，账户%s不足', $group_info['name'], dr_lang('余额')));
                                } else {
                                    // // 不主动删除用户组 情况下保留
                                    $group['timeout'] = 1;
                                    $g[$group['gid']] = $group;
                                }
                                continue;
                            }
                            $group['etime'] = dr_member_group_etime($group_info['days'], $group_info['setting']['dtype']);
                            if (!dr_is_app('pay')) {
                                log_message('error', '用户组自动续费失败：没有安装「支付系统」插件');
                                continue;
                            } else {
                                // 自动续费
                                $rt = $this->add_money($uid, -$price);
                                if (!$rt['code']) {
                                    continue;
                                }
                                // 增加到交易流水
                                $rt = \Phpcmf\Service::M('Pay')->add_paylog([
                                    'uid' => $member['id'],
                                    'username' => $member['username'],
                                    'touid' => 0,
                                    'tousername' => '',
                                    'mid' => 'system',
                                    'title' => dr_lang('用户组（%s）续费', $group_info['name']),
                                    'value' => -$price,
                                    'type' => 'finecms',
                                    'status' => 1,
                                    'result' => dr_lang('有效期至%s', $group['etime'] ? dr_date($group['etime']) : dr_lang('永久')),
                                    'paytime' => SYS_TIME,
                                    'inputtime' => SYS_TIME,
                                ]);
                                // 提醒通知
                                $this->notice(
                                    $uid,
                                    2,
                                    dr_lang('您的用户组（%s）已过期，自动续费成功', $group_info['name']),
                                    \Phpcmf\Service::L('router')->member_url('paylog/show', ['id'=>$rt['code']])
                                );
                            }
                        } else {
                            // 免费组自己续费
                            $group['etime'] = dr_member_group_etime($group_info['days'], $group_info['setting']['dtype']);
                            // 提醒通知
                            $this->notice(
                                $uid,
                                2,
                                dr_lang('您的用户组（%s）已过期，自动免费续期成功，有效期至%s', $group_info['name'], $group['etime'] ? dr_date($group['etime']) : dr_lang('永久'))
                            );
                        }
                        // 更新时间
                        $this->db->table('member_group_index')->where('uid', $uid)->where('gid', $group['gid'])->update(['etime' => $group['etime']]);
                    } else {
                        // 金币
                        $price = (int)$price;
                        if ($price > 0) {
                            // 收费组情况下
                            if ($member[$name] - $price < 0) {
                                // 金币不足 删除
                                if (!$group_info['setting']['outtype'] && $this->delete_group($uid, $group['gid'], 0)) {
                                    // 提醒通知
                                    $this->notice($uid, 2, dr_lang('您的用户组（%s）已过期，自动续费失败，账户%s不足', $group_info['name'], SITE_SCORE));
                                } else {
                                    // false 情况下保留
                                    $group['timeout'] = 1;
                                    $g[$group['gid']] = $group;
                                }
                                continue;
                            }
                            // 自动续费
                            $group['etime'] = dr_member_group_etime($group_info['days'], $group_info['setting']['dtype']);
                            // 自动续费
                            $rt = $this->add_score($uid, -$price, dr_lang('您的用户组（%s）自动续费', $group_info['name']));
                            if (!$rt['code']) {
                                continue;
                            }
                            // 提醒通知
                            $this->notice(
                                $uid,
                                2,
                                dr_lang('您的用户组（%s）已过期，自动续费成功', $group_info['name'])
                            );
                        } else {
                            // 免费组自己续费
                            // 提醒通知
                            $group['etime'] = dr_member_group_etime($group_info['days'], $group_info['setting']['dtype']);
                            // 提醒通知
                            $this->notice(
                                $uid,
                                2,
                                dr_lang('您的用户组（%s）已过期，自动免费续期成功，有效期至%s', $group_info['name'], $group['etime'] ? dr_date($group['etime']) : dr_lang('永久'))
                            );
                        }
                        // 更新时间
                        $this->db->table('member_group_index')->where('uid', $uid)->where('gid', $group['gid'])->update(['etime' => $group['etime']]);
                    }
                } else {
                    // 未开通自动续费直接删除
                    if (!$group_info['setting']['outtype'] && $this->delete_group($uid, $group['gid'], 0)) {
                        // 提醒通知
                        $this->notice($uid, 2, dr_lang('您的用户组（%s）已过期，系统权限已关闭', $group_info['name']));
                    } else {
                        // false 情况下保留
                        $group['timeout'] = 1;
                        $g[$group['gid']] = $group;
                    }
                    continue;
                }
            }
            // 开启自动升级时需要判断等级
            if ($levels
                && \Phpcmf\Service::C()->member_cache['group'][$group['gid']]['setting']['level']['auto']) {
                $value = \Phpcmf\Service::C()->member_cache['group'][$group['gid']]['setting']['level']['unit'] ? $member['spend'] : $member['experience'];
                $level = array_reverse($levels); // 倒序判断
                foreach ($level as $t) {
                    if ($value >= $t['value']) {
                        if ($group['lid'] != $t['id']) {
                            // 开始变更等级
                            // 更新数据
                            $update = [
                                'lid' => $t['id']
                            ];
                            if (\Phpcmf\Service::C()->member_cache['group'][$group['gid']]['setting']['timetype']) {
                                // 按等级计算时间
                                $update['etime'] = dr_member_group_etime(
                                    \Phpcmf\Service::C()->member_cache['group'][$group['gid']]['level'][$t['id']]['setting']['days'],
                                    \Phpcmf\Service::C()->member_cache['group'][$group['gid']]['level'][$t['id']]['setting']['dtype'],
                                    0
                                );
                            }
                            $this->db->table('member_group_index')->where('uid', $uid)->where('gid', $group['gid'])->update($update);
                            /* 等级升级 */
                            $this->notice($uid, 2, dr_lang('您的用户组（%s）等级自动升级为（%s）', \Phpcmf\Service::C()->member_cache['group'][$group['gid']]['name'], $t['name']));
                            $group['lid'] = $t['id'];
                        }
                        break;
                    }
                }
            }
            $g[$group['gid']] = $group;
        }

        return $g;
    }

    // 删除用户组 is_admin 是否是管理员删除，否则就是过期删除
    public function delete_group($uid, $gid, $is_admin = 1) {

        // 回调信息
        $call = $this->member_info($uid);
        $call['group'] = $this->table('member_group_index')->where('gid', $gid)->where('uid', $uid)->getRow();

        $this->db->table('member_group_index')->where('gid', $gid)->where('uid', $uid)->delete();

        // 管理员删除时提醒
        if ($is_admin) {
            $this->notice($uid, 2, dr_lang('您的用户组（%s）被取消', \Phpcmf\Service::C()->member_cache['group'][$gid]['name']));
        }

        // 判断微信标记组
        if (dr_is_app('weixin')) {
            \Phpcmf\Service::C()->init_file('weixin');
            \Phpcmf\Service::M('user', 'weixin')->delete_member_group($uid, $gid);
        }

        // 过期后变更
        if (!$is_admin && \Phpcmf\Service::C()->member_cache['group'][$gid]['setting']['out_gid']
            && \Phpcmf\Service::C()->member_cache['group'][$gid]['setting']['out_gid'] != $gid) {
            $this->insert_group($uid, \Phpcmf\Service::C()->member_cache['group'][$gid]['setting']['out_gid']);
        }

        \Phpcmf\Service::M('member')->clear_cache($uid);

        \Phpcmf\Hooks::trigger('member_del_group_after', $call);

        return true;
    }

    // 新增用户组
    public function insert_group($uid, $gid, $is_notice = 1) {

        $data = [
            'uid' => $uid,
            'gid' => $gid,
            'lid' => 0,
            'stime' => SYS_TIME,
            'etime' => \Phpcmf\Service::C()->member_cache['group'][$gid]['setting']['timetype'] ? 0 : dr_member_group_etime(\Phpcmf\Service::C()->member_cache['group'][$gid]['days'], \Phpcmf\Service::C()->member_cache['group'][$gid]['setting']['dtype']),
        ];
        $rt = $this->table('member_group_index')->insert($data);
        if (!$rt['code']) {
            return;
        }

        $data['id'] = $rt['code'];

        // 挂钩点 用户组变更之后
        $call = $this->member_info($uid);
        $call['group'] = $data;
        $call['group_gid'] = $call['gid'] = $gid;
        $call['group_name'] = \Phpcmf\Service::C()->member_cache['group'][$gid]['name'];
        $is_notice && \Phpcmf\Service::L('Notice')->send_notice('member_edit_group', $call);
        \Phpcmf\Hooks::trigger('member_edit_group_after', $call);

        // 判断微信标记组
        if (dr_is_app('weixin')) {
            \Phpcmf\Service::C()->init_file('weixin');
            \Phpcmf\Service::M('user', 'weixin')->add_member_group($uid, $gid);
        }

        if (!\Phpcmf\Service::C()->member_cache['config']['groups']) {
            // 没开启多个组时，关闭之前的用户组
            $data2 =  $this->db->table('member_group_index')->where('uid', $uid)->where('gid<>' . $gid)->get()->getResultArray();
            if ($data2) {
                foreach ($data2 as $t) {
                    $this->delete_group($uid, $t['gid'], 1);
                }
            }
        }
        \Phpcmf\Service::M('member')->clear_cache($uid);
    }

    // 手动变更等级
    public function update_level($uid, $gid, $lid) {

        $old = $data = $this->db->table('member_group_index')->where('uid', $uid)->where('gid', $gid)->get()->getRowArray();
        $data['gid'] = $gid;
        $data['lid'] = $lid;

        // 更新数据
        $update = [
            'lid' => $lid
        ];
        if (\Phpcmf\Service::C()->member_cache['group'][$gid]['setting']['timetype']) {
            // 按等级计算时间
            $update['etime'] = dr_member_group_etime(
                \Phpcmf\Service::C()->member_cache['group'][$gid]['level'][$lid]['setting']['days'],
                \Phpcmf\Service::C()->member_cache['group'][$gid]['level'][$lid]['setting']['dtype'],
                \Phpcmf\Service::C()->member_cache['group'][$gid]['setting']['timect'] ? $old['etime'] : 0
            );
        }
        $this->db->table('member_group_index')->where('uid', $uid)->where('gid', $gid)->update($update);
        // 挂钩点 用户组变更之后
        $call = $this->member_info($uid);
        $call['group_name'] = \Phpcmf\Service::C()->member_cache['group'][$gid]['name'];
        $call['group_level'] = \Phpcmf\Service::C()->member_cache['group'][$gid]['level'][$lid]['name'];
        \Phpcmf\Service::L('Notice')->send_notice('member_edit_level', $call);
        \Phpcmf\Hooks::trigger('member_edit_level_after', $data, $old);
        \Phpcmf\Service::M('member')->clear_cache($uid);
    }

    // 申请用户组
    public function apply_group($verify_id, $member, $gid, $lid, $price, $my_verify) {

        $group = \Phpcmf\Service::C()->member_cache['group'][$gid];

        if ($group['setting']['verify']) {
            $my_verify['uid'] = (int)$member['id'];
            $my_verify['username'] = (string)$member['username'];
            $my_verify['gid'] = $gid;
            $my_verify['price'] = $group['price'];
            $my_verify['lid'] = $lid;
            $my_verify['status'] = 0;
            $my_verify['content'] = dr_array2string($my_verify['content']);
            $my_verify['inputtime'] = SYS_TIME;
            if ($verify_id) {
                $rt = \Phpcmf\Service::M()->table('member_group_verify')->update($verify_id, $my_verify);
            } else {
                // 被拒再次提交不重复扣款
                $my_verify['price'] = (float)$price;
                $rt = \Phpcmf\Service::M()->table('member_group_verify')->insert($my_verify);
            }
            if (!$rt['code']) {
                return dr_return_data(0, $rt['msg']);
            }
            // 提醒
            $this->admin_notice(0, 'member', $member, dr_lang('用户组[%s]申请审核', $group['name']), 'member/apply/edit:id/'.$rt['code']);
            // 审核
            return dr_return_data(1, dr_lang('等待管理员审核'));
        } else {
            // 直接开通
            $this->insert_group($member['id'], $gid);
            $lid && $this->update_level($member['id'], $gid, $lid);
            if ($my_verify['content']) {
                \Phpcmf\Service::M()->table('member_data')->update($member['id'], $my_verify['content']);
            }

            return dr_return_data(1, dr_lang('开通成功'));
        }
    }

    // 审核用户
    public function verify_member($uid) {

        $this->db->table('member_data')->where('id', $uid)->update(['is_verify' => 1]);
        // 后台提醒
        $this->todo_admin_notice('member/verify/index:field/id/keyword/'.$uid, 0);
        // 审核提醒
        // 注册审核后的通知
        \Phpcmf\Service::L('Notice')->send_notice('member_register_verify', $this->get_member($uid));
    }

    /**
     * 验证登录
     *
     * @param   string  $username   用户名
     * @param   string  $password   明文密码
     * @param   intval  $remember   是否记住密码
     */
    public function login($username, $password, $remember = 0) {

        if (!$username) {
            return dr_return_data(0, dr_lang('账号不能为空'));
        } elseif (!$password) {
            return dr_return_data(0, dr_lang('密码不能为空'));
        }
        // 登录
        $data = $this->_find_member_info($username);
        if (!$data) {
            return dr_return_data(0, dr_lang('用户不存在'));
        }
        // 密码验证
        $password2 = dr_safe_password($password);
        if (md5(md5($password2).$data['salt'].md5($password2)) != $data['password']) {
            if (strlen($password2) == 32 && md5($password2.$data['salt'].$password2) == $data['password']) {
                // 加密验证成功
            } else {
                \Phpcmf\Hooks::trigger('member_login_password_error', [
                    'member' => $data,
                    'password' => $password,
                    'ip' => (string)\Phpcmf\Service::L('input')->ip_address(),
                    'time' => SYS_TIME,
                ]);
                return dr_return_data(0, dr_lang('密码不正确'));
            }
        }

        // 验证管理员登录
        /*
        $rt = $this->_is_admin_login_member($data['id']);
        if (!$rt['code']) {
            return $rt;
        }*/

        // 保存本地会话
        $this->save_cookie($data, $remember);

        // 记录日志
        $this->_login_log($data);

        return dr_return_data(1, 'ok', [
                'auth'=> md5($data['password'].$data['salt']), // API认证字符串,
                'member' => $this->get_member($data['id']),
                'sso' => $this->sso($data, $remember)]
        );
    }

    // 短信登录
    public function login_sms($phone, $remember) {

        $data = $this->db->table('member')->where('phone', $phone)->get()->getRowArray();
        if (!$data) {
            // 未注册
            if (\Phpcmf\Service::C()->member_cache['login']['auto_reg']) {
                // 自动注册
                $groupid = (int)\Phpcmf\Service::C()->member_cache['register']['groupid'];
                if (!$groupid) {
                    return dr_return_data(0, dr_lang('无效的用户组'));
                } elseif (!\Phpcmf\Service::C()->member_cache['group'][$groupid]['register']) {
                    return dr_return_data(0, dr_lang('用户组[%s]不允许注册', \Phpcmf\Service::C()->member_cache['group'][$groupid]['name']));
                }
                $rt = $this->register($groupid, [
                    'username' => '',
                    'phone' => $phone,
                    'email' => '',
                    'password' => SYS_KEY.'_login_sms',
                    'name' => '',
                ]);
                if ($rt['code']) {
                    $data = $rt['data'];
                    $data['uid'] = $data['id'];
                    $this->table('member')->update($rt['code'], [
                        'salt' => 'login_sms'
                    ]);
                } else {
                    return dr_return_data(0, $rt['msg'], ['field' => $rt['data']['field']]);
                }
            } else {
                return dr_return_data(0, dr_lang('手机号码未注册'));
            }
        } else {
            // 记录日志
            $data['uid'] = $data['id'];
            $this->_login_log($data);
        }

        // 保存本地会话
        $this->save_cookie($data, $remember);

        return dr_return_data($data['id'], 'ok', [
                'auth'=> md5($data['password'].$data['salt']), // API认证字符串,
                'member' => $this->get_member($data['id']),
                'sso' => $this->sso($data, $remember)]
        );
    }

    // 绑定注册模式 授权注册绑定
    public function register_oauth_bang($oauth, $groupid, $member, $data = []) {

        if (!$oauth) {
            return dr_return_data(0, dr_lang('OAuth数据不存在，请重试'));
        }

        $rt = $this->register($groupid, $member, $data, $oauth);
        if (!$rt['code']) {
            return dr_return_data(0, $rt['msg']);
        }

        $member = $rt['data'];

        // 保存本地会话
        $this->save_cookie($member);

        // 记录日志
        $this->_login_log($member, $oauth['oauth']);

        // 更改状态
        $this->db->table('member_oauth')->where('id', $oauth['id'])->update(['uid' => $member['id']]);

        // 更新微信插件粉丝表
        if (dr_is_app('weixin') && $oauth['oauth'] == 'wechat') {
            $this->db->table('weixin_user')->where('openid', $oauth['oid'])->update([
                'uid' => $member['id'],
                'username' => $member['username'],
            ]);
        }

        // 同步登录
        $sso = $this->sso($member);

        // 下载头像
        \Phpcmf\Service::L('thread')->cron(['action' => 'oauth_down_avatar', 'id' => $oauth['id'] ]);

        return dr_return_data($member['id'], 'ok', [
            'auth'=> md5($member['password'].$member['salt']), // API认证字符串,
            'member' => $member,
            'sso' => $sso
        ]);
    }

    // 直接登录模式 授权注册
    public function register_oauth($groupid, $oauth) {

        $rt = $this->register($groupid, [
            'username' => '',
            'name' => dr_clear_emoji($oauth['nickname']),
            'email' => '',
            'phone' => '',
        ], null, $oauth);
        if (!$rt['code']) {
            return dr_return_data(0, $rt['msg']);
        }

        $data = $rt['data'];

        // 保存本地会话
        $this->save_cookie($data);

        // 记录日志
        $this->_login_log($data, $oauth['oauth']);

        // 更改状态
        $this->db->table('member_oauth')->where('id', $oauth['id'])->update(['uid' => $data['id']]);
        dr_is_app('weixin') && $oauth['oauth'] == 'wechat' && $this->db->table('weixin_user')->where('openid', $oauth['oid'])->update([
            'uid' => $data['id'],
            'username' => $data['username'],
        ]);

        // 下载头像和同步登录
        $sso = $this->sso($data);
        $sso[] = \Phpcmf\Service::L('router')->member_url('api/avatar', ['id'=>$oauth['id']]);

        return dr_return_data($data['id'], 'ok', [
            'auth'=> md5($data['password'].$data['salt']), // API认证字符串,
            'member' => $data,
            'sso' => $sso
        ]);
    }

    /**
     * 存储授权信息
     */
    public function insert_oauth($uid, $type, $data, $state = '', $back = '') {

        $row = $this->db->table('member_oauth')->where('oid', $data['oid'])->where('oauth', $data['oauth'])->get()->getRowArray();
        if (!$row && $data['unionid']) {
            // 没找到尝试 unionid
            $row = $this->db->table('member_oauth')->where('unionid', $data['unionid'])->get()->getRowArray();
            if (!$uid && $row['uid']) {
                $uid = $row['uid'];
            }
            $ins = 1; // 新插入授权
        } else {
            $ins = 0;
        }

        // 授权更新
        if (!$row || $ins) {
            // 插入授权信息
            $data['uid'] = (int)$uid;
            $rt = $this->table('member_oauth')->insert($data);
            if (!$rt['code']) {
                return dr_return_data(0, $rt['msg']);
            }
            $id = $rt['code'];
        } else {
            // 更新授权信息
            $uid && $data['uid'] = $uid;
            $this->db->table('member_oauth')->where('id', $row['id'])->update($data);
            $id = $row['id'];
        }

        // 绑定成功更新头像
        if ($uid && $data['avatar']) {
            list($cache_path) = dr_avatar_path();
            if (!is_file($cache_path.$uid.'.jpg')) {
                // 没有头像下载头像
                $img = dr_catcher_data($data['avatar']);
                if (strlen($img) > 20 && file_put_contents($cache_path.$uid.'.jpg', $img)) {
                    // 头像状态认证
                    $this->db->table('member_data')->where('id', $uid)->update(['is_avatar' => 1]);
                }
            }
        }

        // 存储
        \Phpcmf\Service::L('cache')->set_auth_data('member_auth_'.$type.'_'.$data['oauth'].'_'.$id, $id);

        return dr_return_data($id, $type == 'login' ? \Phpcmf\Service::L('router')->member_url('login/oauth', ['id' => $id, 'name' => $data['oauth'], 'state' => $state, 'back' => $back]) : \Phpcmf\Service::L('router')->member_url('account/oauth', ['id' => $id, 'name' => $data['oauth']]));
    }

    // 删除会员后执行 sync是否删除相关数据表
    public function member_delete($id, $sync = 0) {

        $this->clear_cache($id);

        // 删除会员的相关表
        $this->db->table('member')->where('id', $id)->delete();
        $this->db->table('member_data')->where('id', $id)->delete();
        $this->db->table('member_group_index')->where('uid', $id)->delete();
        $this->db->table('member_login')->where('uid', $id)->delete();
        $this->db->table('member_oauth')->where('uid', $id)->delete();
        $this->db->table('admin')->where('uid', $id)->delete();
        $this->db->table('admin_login')->where('uid', $id)->delete();
        $this->db->table('admin_role_index')->where('uid', $id)->delete();
        $this->db->table('member_group_verify')->where('uid', $id)->delete();
        $this->is_table_exists('member_paylog') && $this->db->table('member_paylog')->where('uid', $id)->delete();
        $this->is_table_exists('member_scorelog') && $this->db->table('member_scorelog')->where('uid', $id)->delete();
        $this->is_table_exists('member_explog') && $this->db->table('member_explog')->where('uid', $id)->delete();
        $this->is_table_exists('member_cashlog') && $this->db->table('member_cashlog')->where('uid', $id)->delete();
        $this->is_table_exists('member_notice') && $this->db->table('member_notice')->where('uid', $id)->delete();
        $this->delete_admin_notice('member/verify/index:field/id/keyword/'.$id, 0);

        // 删除头像
        list($cache_path, $cache_url) = dr_avatar_path();
        if (is_file($cache_path.$id.'.jpg')) {
            unlink($cache_url.$id.'.jpg');
        }

        // 删除微信uid
        if (dr_is_app('weixin') && $this->is_table_exists('weixin_user')) {
            $this->db->table('weixin_user')->where('uid', $id)->update([
                'uid' => 0,
                'username' => '',
            ]);
        }

        if (!$sync) {
            return ;
        }

        // 同步删除动作
        \Phpcmf\Service::M('Sync')->delete_member($id);

        // 按站点数据删除
        SYS_ATTACHMENT_DB && \Phpcmf\Service::M('Attachment')->uid_delete($id);
        foreach ($this->site as $siteid) {
            // 表单
            if ($this->db->query("SHOW TABLES LIKE '".$this->dbprefix($siteid . '_form')."'")->getRowArray()) {
                $form = $this->is_table_exists($siteid . '_form') ? $this->init(['table' => $siteid . '_form'])->getAll() : [];
                if ($form) {
                    foreach ($form as $t) {
                        $table = $siteid . '_form_' . $t['table'];
                        \Phpcmf\Service::M()->db->tableExists(\Phpcmf\Service::M()->dbprefix($table)) && $this->db->table($table)->where('uid', $id)->delete();
                        for ($i = 0; $i < 200; $i++) {
                            if (!$this->db->query("SHOW TABLES LIKE '" . $this->dbprefix($table) . '_data_' . $i . "'")->getRowArray()) {
                                break;
                            }
                            $this->db->table($table . '_data_' . $i)->where('uid', $id)->delete();
                        }
                    }
                }
            }
            // 模块
            if ($this->db->query("SHOW TABLES LIKE '".$this->dbprefix('module')."'")->getRowArray()) {
                $module = $this->table('module')->getAll();
                if ($module) {
                    foreach ($module as $m) {
                        $mdir = $m['dirname'];
                        $table = $siteid.'_'.$mdir;
                        // 模块内容
                        if (!$this->db->query("SHOW TABLES LIKE '".$this->dbprefix($table)."'")->getRowArray()) {
                            break;
                        }
                        $mdb = \Phpcmf\Service::M('Content', $mdir);
                        $mdb->_init($mdir, $siteid);
                        // 查询删除内容
                        $index = $this->table($table.'_index')->where('uid', $id)->getAll();
                        if ($index) {
                            foreach ($index as $t) {
                                $mdb->delete_content($t['id']);
                            }
                        }
                        $form = $this->is_table_exists('module_form') ? $this->db->table('module_form')->where('module', $mdir)->get()->getResultArray() : [];
                        if ($form) {
                            foreach ($form as $t) {
                                $mytable = $table.'_form_'.$t['table'];
                                if (!$this->db->query("SHOW TABLES LIKE '".$this->dbprefix($mytable)."'")->getRowArray()) {
                                    break;
                                }
                                $this->db->table($mytable)->where('uid', $id)->delete();
                                for ($i = 0; $i < 200; $i ++) {
                                    if (!$this->db->query("SHOW TABLES LIKE '".$this->dbprefix($mytable).'_data_'.$i."'")->getRowArray()) {
                                        break;
                                    }
                                    $this->db->table($mytable.'_data_'.$i)->where('uid', $id)->delete();
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // 缓存动作
    public function member_cache() {

        // 审核流程
        $data = $this->table('admin_verify')->getAll();
        $verify = [];
        if ($data) {
            foreach ($data as $t) {
                $t['value'] = dr_string2array($t['verify']);
                unset($t['verify']);
                $verify[$t['id']] = $t;
            }
        }
        \Phpcmf\Service::L('cache')->set_file('verify', $verify);

        // 获取会员全部配置信息
        $cache = [];
        $result = $this->db->table('member_setting')->get()->getResultArray();
        if ($result) {
            foreach ($result as $t) {
                $cache[$t['name']] = dr_string2array($t['value']);
            }
        }

        if (!isset($cache['list_field']) || !$cache['list_field']) {
            $cache['list_field'] = array (
                'username' =>
                    array (
                        'use' => '1',
                        'name' => '账号',
                        'width' => '110',
                        'func' => 'author',
                    ),
                'group' =>
                    array (
                        'func' => 'group',
                        'center' => '1',
                    ),
                'name' =>
                    array (
                        'use' => '1',
                        'name' => '姓名',
                        'width' => '120',
                        'func' => '',
                    ),
                'money' =>
                    array (
                        'use' => '1',
                        'name' => '余额',
                        'width' => '120',
                        'func' => 'money',
                    ),
                'score' =>
                    array (
                        'use' => '1',
                        'name' => '积分',
                        'width' => '120',
                        'func' => 'score',
                    ),
                'regip' =>
                    array (
                        'use' => '1',
                        'name' => '注册IP',
                        'width' => '140',
                        'func' => 'ip',
                    ),
                'regtime' =>
                    array (
                        'use' => '1',
                        'name' => '注册时间',
                        'width' => '170',
                        'func' => 'datetime',
                    ),
                'is_lock' =>
                    array (
                        'func' => 'save_select_value',
                        'center' => '1',
                    ),
            );
        }

        // 字段归属
        $cache['myfield'] = $cache['field'];

        // 自定义字段
        $register_field = $group_field = $cache['field'] = [];
        $field = $this->db->table('field')->where('disabled', 0)->where('relatedname', 'member')->orderBy('displayorder ASC,id ASC')->get()->getResultArray();
        if ($field) {
            foreach ($field as $f) {
                $f['setting'] = dr_string2array($f['setting']);
                $cache['field'][$f['fieldname']] = $f;
                // 归类用户组字段
                if ($cache['myfield'][$f['id']]) {
                    foreach ($cache['myfield'][$f['id']] as $gid) {
                        $group_field[$gid][] = $f['fieldname'];
                    }
                }
                // 归类可用注册的字段
                if ($cache['register_field'][$f['id']]) {
                    $register_field[] = $f['fieldname'];
                }
            }
        }

        // 支付接口
        if ($cache['payapi']) {
            foreach ($cache['payapi'] as $i => $t) {
                if (!$t['use']) {
                    unset($cache['payapi'][$i]);
                }
            }
        }

        // 注册配置
        $cache['register']['notallow'] = explode(',', trim((string)$cache['register']['notallow']));

        // 用户组
        $cache['register']['group'] = [];
        $group = $this->db->table('member_group')->orderBy('displayorder ASC,id ASC')->get()->getResultArray();
        if ($group) {
            foreach ($group as $t) {
                $level = $this->db->table('member_level')->where('gid', $t['id'])->orderBy('displayorder ASC,id ASC')->get()->getResultArray();
                if ($level) {
                    foreach ($level as $lv) {
                        $lv['icon'] = dr_get_file($lv['stars']);
                        $lv['setting'] = dr_string2array($lv['setting']);
                        $cache['authid'][] = $t['id'].'-'.$lv['id'];
                        $t['level'][$lv['id']] = $lv;
                    }
                } else {
                    $cache['authid'][] = $t['id'];
                }
                $t['setting'] = dr_string2array($t['setting']);
                // 用户组的可用字段
                $t['field'] = $group_field[$t['id']];
                // 当前用户组开启了注册时, 查询它可注册的字段
                $t['register'] && $t['field'] && $t['register_field'] = $register_field ? dr_array_intersect($t['field'], $register_field) : [];
                // 是否允许注册
                $t['register'] && $cache['register']['group'][] = $t['id'];
                $cache['group'][$t['id']] = $t;
            }
        }

        \Phpcmf\Service::L('cache')->set_file('member', $cache);

        return $cache;
    }
}
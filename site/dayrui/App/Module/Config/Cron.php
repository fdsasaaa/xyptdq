<?php

$code = file_get_contents(CMSPATH.'Control/Api/Run.php');
if ($code && strpos($code, 'post_time')) {
    return; // 老程序不执行
}

// 批量执行站点动作
foreach ($this->site_info as $siteid => $site) {
    // 模块
    $module = \Phpcmf\Service::L('cache')->get('module-'.$siteid.'-content');
    if ($module) {
        foreach ($module as $dir => $mod) {
            // 删除模块首页
            if ($mod['is_index_html']) {
                if ($mod['domain']) {
                    // 绑定域名时
                    $file = 'index.html';
                } else {
                    $file = ltrim(\Phpcmf\Service::L('Router')->remove_domain($mod['url']), '/'); // 从地址中获取要生成的文件名;
                }
                if ($file) {
                    unlink(\Phpcmf\Service::L('html')->get_webpath($siteid, $dir, $file));
                    unlink(\Phpcmf\Service::L('html')->get_webpath($siteid, $dir, 'mobile/'.$file));
                }
            }
            // 定时发布动作
            $times = \Phpcmf\Service::M()->table($siteid.'_'.$dir.'_time')->where('posttime > 0 and posttime < '.SYS_TIME)->getAll(1);
            if ($times) {
                $lockFile = WRITEPATH."config/module_cron_".$siteid.$dir.".lock";
                if (file_exists($lockFile)) {
                    $ctime = intval(filectime($lockFile));
                    if (SYS_TIME - $ctime > 1000) {
                        unlink($lockFile);
                    } else {
                        CI_DEBUG && log_message('debug', '定时发布文件锁定：'.date("Y-m-d H:i:s", $ctime));
                        exit;
                    }
                }
                $fp = fopen($lockFile, 'w');
                if ($fp) {
                    // 获取锁成功，执行你的代码
                    chmod($lockFile, 0666); // 确保文件有足够权限
                    $this->_module_init($dir, $siteid, 1);
                    \Phpcmf\Service::C()->module = $this->module;
                    \Phpcmf\Service::C()->content_model->siteid = $siteid;
                    \Phpcmf\Service::C()->content_model->_init($dir, $siteid);
                    foreach ($times as $t) {
                        $rt = $this->content_model->post_time($t);
                        if (!$rt['code']) {
                            echo '模块【'.$dir.'】定时发布（'.$t['id'].'）失败'.PHP_EOL;
                            CI_DEBUG && log_message('error', '模块【'.$dir.'】定时发布（'.$t['id'].'）失败：'.$rt['msg']);
                        } else {
                            \Phpcmf\Service::M()->table($siteid.'_'.$dir.'_time')->update($t['id'], [
                                'posttime' => 0,
                            ]);
                            echo '模块【'.$dir.'】定时发布（'.$rt['code'].'）成功'.PHP_EOL;
                        }
                        sleep(10);
                    }
                    // 执行完毕后释放锁
                    fclose($fp);
                    unlink($lockFile);
                    break;
                } else {
                    CI_DEBUG && log_message('debug', '定时发布文件上锁成功：'.date("Y-m-d H:i:s"));
                    exit;
                }
            }
        }
    }
}
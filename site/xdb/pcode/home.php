<?php

class  Home extends \Xunruicms
{
    public function index()
    {

        $this->template->assign([
            'class' => 'index',
            'meta_title' => '迅睿数据备份',
        ]);
        $this->template->display('q.html');exit;
    }

    public function error()
    {

        $this->template->assign([
            'class' => 'error',
            'meta_title' => '迅睿数据备份',
        ]);
        $this->template->display('q_error.html');exit;
    }


    public function old()
    {

        $this->template->assign([
            'class' => 'index',
            'meta_title' => '迅睿数据备份',
        ]);

        $st = isset($_GET['st']) ? intval($_GET['st']) : 0;
        if ($st == 9) {

            $path = [
                WRITEPATH.'attach',
                WRITEPATH.'file',
                WRITEPATH.'template',
                WRITEPATH.'debugbar',
                WRITEPATH.'authcode',
                WRITEPATH.'debugbar',
                WRITEPATH.'session',
                WRITEPATH.'thread',
                WRITEPATH.'temp',
            ];
            foreach ($path as $t) {
                dr_dir_delete($t);
                dr_mkdirs($t);
            }

            // 备份数据库
            $db = [];
            require CONFIGPATH.'database.php';

            $mysqli = function_exists('mysqli_init') ? mysqli_init() : 0;
            if (!$mysqli) {
                $this->_json(0, 'PHP环境必须启用Mysqli扩展');
            } elseif (!mysqli_real_connect($mysqli, $db['default']['hostname'], $db['default']['username'], $db['default']['password'], $db['default']['database'])) {
                $this->_json(0, '['.mysqli_connect_errno().'] - 无法连接到数据库服务器（'.$db['default']['db_host'].'），请检查用户名（'.$db['default']['db_user'].'）和密码（'.$data['db_pass'].'）是否正确');
            }
            if (!mysqli_set_charset($mysqli, "utf8mb4")) {
                $this->_json(0, "当前MySQL不支持utf8mb4编码（".mysqli_error($mysqli)."）");
            }

            $rs = $mysqli->query("SHOW TABLES FROM `".$db['default']['database']."`");
            $tables = [];
            while($obj = $rs->fetch_assoc()){
                $tables[] = end($obj);
            }

            if (!$tables) {
                $this->_json(0, "没有找到数据表");
            }

            $sql = '';
            // 表结构
            foreach ($tables as $table) {
                $rs = $mysqli->query("show create table `".$table."`");
                $obj = $rs->fetch_array();
                $sql.= PHP_EOL.'DROP TABLE IF EXISTS `'.$table.'`;<XUNRUICMS_DB_LINE>';
                $sql.= PHP_EOL.$obj[1].';<XUNRUICMS_DB_LINE>';
            }

            file_put_contents(WEBPATH.'cache/db/tables.sql', $sql);
            file_put_contents(WEBPATH.'cache/db/tables.json', json_encode($tables));

            $this->_json(1, '表结构备份成功，即将进行表数据备份...', [
                'url' => '/xdb/index.php?c=home&m=old&st=8'
            ]);
        } elseif ($st == 8) {
            // 备份结构
            $db = [];
            require CONFIGPATH.'database.php';

            $mysqli = function_exists('mysqli_init') ? mysqli_init() : 0;
            if (!$mysqli) {
                $this->_msg(0, 'PHP环境必须启用Mysqli扩展');
            } elseif (!mysqli_real_connect($mysqli, $db['default']['hostname'], $db['default']['username'], $db['default']['password'], $db['default']['database'])) {
                $this->_msg(0, '['.mysqli_connect_errno().'] - 无法连接到数据库服务器（'.$db['default']['db_host'].'），请检查用户名（'.$db['default']['db_user'].'）和密码（'.$data['db_pass'].'）是否正确');
            }
            if (!mysqli_set_charset($mysqli, "utf8mb4")) {
                $this->_msg(0, "当前MySQL不支持utf8mb4编码（".mysqli_error($mysqli)."）");
            }

            $tables = json_decode(file_get_contents(WEBPATH.'cache/db/tables.json'), true);
            if (!$tables) {
                $this->_msg(0, "没有找到数据表");
            }

            $key = intval($_GET['key']);
            $page = intval($_GET['page']);

            $url = '/xdb/index.php?c=home&m=old&st=8&';

            if (isset($tables[$key]) && $tables[$key]) {
                // 备份单表数据
                $table = $tables[$key];
                $rs = $mysqli->query("select * from `".$table."`  limit ".($page*100).", 100;");
                $nums = mysqli_num_rows($rs);
                if ($nums) {
                    $sql = '';
                    $list = mysqli_fetch_all($rs,MYSQLI_ASSOC);
                    foreach ($list as $row) {
                        $sqlTab = "REPLACE INTO `".$table."` (";
                        $sqlStr = ") VALUES (";
                        foreach($row as $r => $zd){
                            $sqlTab .= "`".$r."`, ";
                            $sqlStr .= "'".addslashes((string)$zd)."', ";
                        }
                        //去掉最后一个逗号和空格
                        $sqlTab = substr($sqlTab,0,strlen($sqlTab)-2);
                        $sqlStr = $sqlTab.substr($sqlStr,0,strlen($sqlStr)-2);
                        $sqlStr .= ");<XUNRUICMS_DB_LINE>";
                        $sql.= PHP_EOL.$sqlStr;
                    }
                    // 域名替换
                    $site = require WRITEPATH.'config/site.php';
                    $system = require WRITEPATH.'config/system.php';
                    $http_prefix = $system['SYS_HTTPS'] ? 'https://' : 'http://';
                    if ($site[1]['SITE_DOMAIN']) {
                        $sql = str_replace($http_prefix.$site[1]['SITE_DOMAIN'], 'WEB_DOMAIN_XUNRUICMS_URL', $sql);
                        $sql = str_replace($site[1]['SITE_DOMAIN'], 'WEB_DOMAIN_XUNRUICMS', $sql);
                    }
                    if ($site[1]['SITE_MOBILE']) {
                        $sql = str_replace($http_prefix.$site[1]['SITE_MOBILE'], 'WEB_DOMAIN_XUNRUICMS_MOBILE_URL', $sql);
                        $sql = str_replace($site[1]['SITE_MOBILE'], 'WEB_DOMAIN_XUNRUICMS_MOBILE', $sql);
                    }

                    file_put_contents(WEBPATH.'cache/db/tables_'.$key.'_'.$page.'.sql', $sql);

                    $page++;
                    $this->_msg(1, '备份表'.$table.'，进行中('.$page.')...', $url.'key='.$key.'&page='.$page);
                } else {
                    // 没数据，下一页
                    $this->_msg(1, '备份表'.$table.'，进行中...', $url.'key='.($key+1));
                }

            } else {
                $this->_msg(1, '即将完成...', '/xdb/index.php?c=home&m=old');
            }

        } else {
            $this->template->display('q_old.html');
        }
        exit;
    }

    public function after()
    {

        $tables = json_decode(file_get_contents(WEBPATH.'cache/db/tables.json'), true);
        if (!$tables) {
            $this->_msg(0, "没有找到备份数据");
        }

        $st = isset($_GET['st']) ? intval($_GET['st']) : 0;
        if ($st == 1) {
            set_time_limit(0);
            $data = $_POST['data'];
            if (empty($data['db_host'])) {
                $this->_json(0, '数据库地址不能为空');
            } elseif (empty($data['db_user'])) {
                $this->_json(0, '数据库账号不能为空');
            } elseif (empty($data['db_name'])) {
                $this->_json(0, '数据库名称不能为空');
            } elseif (empty($data['db_pass'])) {
                $this->_json(0, '数据库密码不能为空');
            } elseif (is_numeric($data['db_name'])) {
                $this->_json(0, '数据库名称不能是数字');
            } elseif (strpos($data['db_name'], '.') !== false) {
                $this->_json(0, '数据库名称不能存在.号');
            }

            $mysqli = function_exists('mysqli_init') ? mysqli_init() : 0;
            if (!$mysqli) {
                $this->_json(0, '您的PHP环境必须启用Mysqli扩展');
            } elseif (!mysqli_real_connect($mysqli, $data['db_host'], $data['db_user'], $data['db_pass'])) {
                $this->_json(0, '['.mysqli_connect_errno().'] - 无法连接到数据库服务器（'.$data['db_host'].'），请检查用户名（'.$data['db_user'].'）和密码（'.$data['db_pass'].'）是否正确');
            } elseif (!mysqli_select_db($mysqli, $data['db_name'])) {
                if (!mysqli_query($mysqli, 'CREATE DATABASE '.$data['db_name'])) {
                    $this->_json(0, '指定的数据库（'.$data['db_name'].'）不存在，系统尝试创建失败，请通过其他方式建立数据库');
                }
            }
            if (!mysqli_set_charset($mysqli, "utf8mb4")) {
                $this->_json(0, "当前MySQL不支持utf8mb4编码（".mysqli_error($mysqli)."）");
            }

            // 写入配置
            $site = require WRITEPATH.'config/site.php';
            $system = require WRITEPATH.'config/system.php';
            $prefix = $system['SYS_HTTPS'] ? 'https://' : 'http://';

            if ($data['domain']) {
                $data['domain'] = trim($data['domain'], '/');
            }

            if ($data['mdomain']) {
                $data['mdomain'] = trim($data['mdomain'], '/');
            }

            $rp = [];
            foreach ($site as $i => $t) {
                // 替换主域名
                $site[$i]['SITE_LOGO'] = str_replace($prefix.$t['SITE_DOMAIN'], $data['domain'], $t['SITE_LOGO']);
                $site[$i]['SITE_DOMAIN'] = str_replace(['https://', 'http://'], '', $data['domain']);
                if ($prefix.$t['SITE_DOMAIN'] != $data['domain']) {
                    $rp[] = [$prefix.$t['SITE_DOMAIN'], $data['domain']];
                }
                if ($t['SITE_DOMAIN'] != $site[$i]['SITE_DOMAIN']) {
                    $rp[] = [$t['SITE_DOMAIN'], $site[$i]['SITE_DOMAIN']];
                }

                $rp[] = ['WEB_DOMAIN_XUNRUICMS_URL', $data['domain']];
                $rp[] = ['WEB_DOMAIN_XUNRUICMS', $site[$i]['SITE_DOMAIN']];
                if ($t['SITE_MOBILE']) {
                    if ($prefix.$t['SITE_MOBILE'] != $data['mdomain']) {
                        $rp[] = [$prefix.$t['SITE_MOBILE'], $data['mdomain']];
                    }
                    $site[$i]['SITE_MOBILE'] = str_replace(['https://', 'http://'], '', $data['mdomain']);
                    if ($t['SITE_MOBILE'] != $site[$i]['SITE_MOBILE']) {
                        $rp[] = [$t['SITE_MOBILE'], $site[$i]['SITE_MOBILE']];
                    }

                    $rp[] = ['WEB_DOMAIN_XUNRUICMS_MOBILE_URL', $data['mdomain']];
                    $rp[] = ['WEB_DOMAIN_XUNRUICMS_MOBILE', $site[$i]['SITE_MOBILE']];
                }
                break;
            }
            $this->file(WEBPATH.'cache/site.php', '站点配置文件', 32)->to_require($site);
            $this->file(WEBPATH.'cache/rp.php', '站点配置文件', 32)->to_require($rp);


            $db = [];
            $db['default'] = [];
            require CONFIGPATH.'database.php';

            if (!isset($db['default']['DBPrefix'])) {
                $this->_json(0, '未抓到数据库表前缀');
            }

            // 存储mysql
            $database = '<?php

/**
 * 数据库配置文件
 */

$db[\'default\']	= [
    \'hostname\'	=> \''.$data['db_host'].'\',
    \'username\'	=> \''.$data['db_user'].'\',
    \'password\'	=> \''.$data['db_pass'].'\',
    \'database\'	=> \''.$data['db_name'].'\',
    \'DBPrefix\'	=> \''.dr_safe_filename($db['default']['DBPrefix']).'\',
];';
            $size = file_put_contents(CONFIGPATH.'database.php', $database);
            if (!$size || $size < 10) {
                $this->_json(0, '数据库配置文件创建失败，config目录无法写入');
            }

            $tables = file_get_contents(WEBPATH.'cache/db/tables.sql');
            if (!$tables) {
                $this->_json(0, '没有识别到数据库表结构文件：'.WEBPATH.'cache/db/tables.sql');
            }
            $list = explode('<XUNRUICMS_DB_LINE>', $tables);
            foreach ($list as $sql) {
                $sql = trim($sql);
                $sql && mysqli_query($mysqli, $sql);
            }

            file_put_contents(WEBPATH.'cache/db/error.sql', '');
            $this->_json(1, '数据库配置成功，即将下一步...', [
                'url' => '/xdb/index.php?c=home&m=after&st=2'
            ]);
        } elseif ($st == 2) {
            // 恢复数据
            $db = [];
            require CONFIGPATH.'database.php';
            $mysqli = function_exists('mysqli_init') ? mysqli_init() : 0;
            if (!$mysqli) {
                $this->_msg(0, 'PHP环境必须启用Mysqli扩展');
            } elseif (!mysqli_real_connect($mysqli, $db['default']['hostname'], $db['default']['username'], $db['default']['password'], $db['default']['database'])) {
                $this->_msg(0, '['.mysqli_connect_errno().'] - 无法连接到数据库服务器（'.$db['default']['db_host'].'），请检查用户名（'.$db['default']['db_user'].'）和密码（'.$data['db_pass'].'）是否正确');
            }
            if (!mysqli_set_charset($mysqli, "utf8mb4")) {
                $this->_msg(0, "当前MySQL不支持utf8mb4编码（".mysqli_error($mysqli)."）");
            }

            $key = intval($_GET['key']);
            $page = intval($_GET['page']);

            $url = '/xdb/index.php?c=home&m=after&st=2&';
            if (isset($tables[$key]) && $tables[$key]) {
                // 恢复单表数据
                $table = $tables[$key];
                $file = WEBPATH.'cache/db/tables_'.$key.'_'.$page.'.sql';
                if (!is_file($file)) {
                    // 此表无数据
                    $this->_msg(1, '恢复表'.$table.'，进行中...', $url.'key='.($key+1));
                }
                $sql = file_get_contents($file);
                $list = explode('<XUNRUICMS_DB_LINE>', $sql);
                $rp = require WEBPATH.'cache/rp.php';
                foreach ($list as $sql) {
                    $sql = trim($sql);
                    if ($sql) {
                        if ($rp) {
                            foreach ($rp as $t) {
                                list($a, $b) = $t;
                                $sql = str_replace($a, $b, $sql);
                            }
                        }
                        if (!@mysqli_query($mysqli, $sql)) {
                            file_put_contents(WEBPATH.'cache/db/error.sql', $sql.PHP_EOL, FILE_APPEND);
                        }
                    }
                }
                $page ++;
                $file = WEBPATH.'cache/db/tables_'.$key.'_'.$page.'.sql';
                if (is_file($file)) {
                    $this->_msg(1, '恢复表'.$table.'，进行中('.$page.')...', $url.'key='.$key.'&page='.$page);
                } else {
                    // 没数据，下一页
                    $this->_msg(1, '恢复表'.$table.'，进行中...', $url.'key='.($key+1));
                }
            } else {
                copy(WEBPATH.'cache/site.php', WRITEPATH.'config/site.php');
                $this->template->assign([
                    'error' => file_get_contents(WEBPATH.'cache/db/error.sql'),
                    'class' => 'after',
                    'meta_title' => '迅睿数据备份',
                ]);
                $this->template->display('q_ok.html');
            }
        } else {
            $db = [];
            $db['default'] = [];
            require CONFIGPATH.'database.php';
            $domain = $mdomain = '';
            $site = require WRITEPATH.'config/site.php';
            $system = require WRITEPATH.'config/system.php';
            $http_prefix = $system['SYS_HTTPS'] ? 'https://' : 'http://';
            if ($site[1]['SITE_DOMAIN']) {
                $domain = $http_prefix.$site[1]['SITE_DOMAIN'];
            }
            if ($site[1]['SITE_MOBILE']) {
                $mdomain = $http_prefix.$site[1]['SITE_MOBILE'];
            }
            $this->template->assign([
                'db' => $db['default'],
                'class' => 'after',
                'meta_title' => '迅睿数据备份',
                'domain' => $domain,
                'mdomain' => $mdomain,
            ]);
            $this->template->display('q_after.html');
        }

        exit;
    }
}

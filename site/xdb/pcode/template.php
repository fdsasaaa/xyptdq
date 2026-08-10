<?php

if (!defined('BASEPATH'))
    exit('No direct script access allowed');
/**
 * 模板解析文件
 */
class template {

    public $ci; // ci控制器对象
    public $_dir = WEBPATH.'template/'; // 模板目录
    public $_cache = WEBPATH.'cache/tpl/'; // 模板缓存目录
    public $_options; // 模板变量
    public $_filename; // 主模板名称
    public $_include_file; // 引用计数
    public $pagination; // 自定义分页查询

    /**
     * 输出模板
     */
    public function display($_name, $_dir = NULL) {

        // 处理变量
        $this->_options['ci'] = $this->ci;
        extract($this->_options, EXTR_PREFIX_SAME, 'data');
        $this->_options = NULL;
        $this->_filename = $_name;

        ob_end_clean();

        // 加载编译后的缓存文件
        include $this->load_view_file($this->get_file_name($_name, $_dir));

        // 消毁变量
        $this->_include_file = NULL;
    }

    /**
     * 设置模型/应用的模板目录
     */
    public function get_file_name($file) {

        if (is_file($this->_dir.$file)) {
            return $this->_dir.$file;
        }

        show_error('模板文件 ('.$file.') 不存在！');
    }

    /**
     * 设置模板变量
     */
    public function assign($key, $value = NULL) {

        if (!$key) {
            return FALSE;
        }

        if (is_array($key)) {
            foreach ($key as $k => $v) {
                $this->_options[$k] = $v;
            }
        } else {
            $this->_options[$key] = $value;
        }
    }

    /**
     * 获取模板变量
     */
    public function get_value($key) {

        if (!$key) {
            return NULL;
        }

        return $this->_options[$key];
    }

    /**
     * 模板标签include/template
     *
     * @param	string	$name	模板文件
     * @param	string	$dir	应用、模型目录
     * @return  bool
     */
    public function _include($name, $dir = NULL) {

        $file = $this->get_file_name($name, $dir, TRUE);
        $fname = md5($file);
        $this->_include_file[$fname] ++;

        $this->_include_file[$fname] > 50 && show_error('模板文件 ('.str_replace(WEBPATH, '/', $file).') 标签template引用文件目录结构错误', 200, '模板结构错误');

        return $this->load_view_file($file);
    }

    /**
     * 模板标签load
     *
     * @param	string	$file	模板文件
     * @return  bool
     */
    public function _load($file) {

        $fname = md5($file);
        $this->_include_file[$fname] ++;

        $this->_include_file[$fname] > 50 && show_error('模板文件 ('.str_replace(WEBPATH, '/', $file).') 标签load引用文件目录结构错误', 200, '模板结构错误');

        return $this->load_view_file($file);
    }

    /**
     * 加载
     *
     * @param	string
     * @return  string
     */
    public function load_view_file($name) {

        $cache_file = $this->_cache.str_replace(array(WEBPATH, '/', '\\', DIRECTORY_SEPARATOR), array('', '.', '.', '.'), $name).'.cache.php';

        // 当缓存文件不存在时或者缓存文件创建时间少于了模板文件时,再重新生成缓存文件
        //if (!is_file($cache_file) || (is_file($cache_file) && is_file($name) && filemtime($cache_file) < filemtime($name))) {
        if (1) {
            $content = $this->handle_view_file(file_get_contents($name));
            // 执行任务队列代码
            @file_put_contents($cache_file, $content, LOCK_EX) === FALSE && show_error('请将模板缓存目录（/cache/tpl/）权限设为777');
        }

        return $cache_file;
    }

    // 将模板代码转化为php
    public function code2php($code) {

        $file = md5($code).'.code.php';
        !is_file($this->_cache.$file) && @file_put_contents($this->_cache.$file, str_replace('$this->', '$this->ci->template->', $this->handle_view_file($code)));

        return $this->_cache.$file;
    }

    /**
     * 解析模板文件
     *
     * @param	string
     * @param	string
     * @return  string
     */
    public function handle_view_file($view_content) {

        if (!$view_content) {
            return '';
        }

        // 正则表达式匹配的模板标签
        $regex_array = array(
            // 站点缓存数据变量
            '#{([A-Z\-]+)\.(.+)}#U',
            // 3维数组变量
            '#{\$(\w+?)\.(\w+?)\.(\w+?)\.(\w+?)}#i',
            // 2维数组变量
            '#{\$(\w+?)\.(\w+?)\.(\w+?)}#i',
            // 1维数组变量
            '#{\$(\w+?)\.(\w+?)}#i',
            // 3维数组变量
            '#\$(\w+?)\.(\w+?)\.(\w+?)\.(\w+?)#Ui',
            // 2维数组变量
            '#\$(\w+?)\.(\w+?)\.(\w+?)#Ui',
            // 1维数组变量
            '#\$(\w+?)\.(\w+?)#Ui',
            // PHP函数
            '#{([a-z_0-9]+)\((.*)\)}#Ui',
            // PHP常量
            '#{([A-Z_]+)}#',
            // PHP变量
            '#{\$(.+?)}#i',
            // 引入模板
            '#{\s*template\s+"([\$\-_\/\w\.]+)",\s*"(.+)"\s*}#Uis',
            '#{\s*template\s+"([\$\-_\/\w\.]+)",\s*MOD_DIR\s*}#Uis',
            '#{\s*template\s+"([\$\-_\/\w\.]+)"\s*}#Uis',
            '#{\s*template\s+([\$\-_\/\w\.]+)\s*}#Uis',
            // 加载指定文件到模板
            '#{\s*load\s+"([\$\-_\/\w\.]+)"\s*}#Uis',
            '#{\s*load\s+([\$\-_\/\w\.]+)\s*}#Uis',
            // php标签
            '#{php\s+(.+?)}#is',
            // list标签
            '#{list\s+(.+?)return=(.+?)\s?}#i',
            '#{list\s+(.+?)\s?}#i',
            '#{\s?\/list\s?}#i',
            // if判断语句
            '#{\s?if\s+(.+?)\s?}#i',
            '#{\s?else\sif\s+(.+?)\s?}#i',
            '#{\s?else\s?}#i',
            '#{\s?\/if\s?}#i',
            // 循环语句
            '#{\s?loop\s+\$(.+?)\s+\$(\w+?)\s?\$(\w+?)\s?}#i',
            '#{\s?loop\s+\$(.+?)\s+\$(\w+?)\s?}#i',
            '#{\s?loop\s+\$(.+?)\s+\$(\w+?)\s?=>\s?\$(\w+?)\s?}#i',
            '#{\s?\/loop\s?}#i',
            // 结束标记
            '#{\s?php\s?}#i',
            '#{\s?\/php\s?}#i',
            '#\?\>\s*\<\?php\s#s',
        );

        // 替换直接变量输出
        $replace_array = array(
            "<?php \$cache = \$this->_cache_var('\\1'); @eval('echo \$cache'.\$this->_get_var('\\2').';');unset(\$cache); ?>",
            "<?php echo \$\\1['\\2']['\\3']['\\4']; ?>",
            "<?php echo \$\\1['\\2']['\\3']; ?>",
            "<?php echo \$\\1['\\2']; ?>",
            "\$\\1['\\2']['\\3']['\\4']",
            "\$\\1['\\2']['\\3']",
            "\$\\1['\\2']",
            "<?php echo \\1(\\2); ?>",
            "<?php echo \\1; ?>",
            "<?php echo \$\\1; ?>",
            "<?php if (\$fn_include = \$this->_include(\"\\1\", \"\\2\")) include(\$fn_include); ?>",
            "<?php if (\$fn_include = \$this->_include(\"\\1\", \"MOD_DIR\")) include(\$fn_include); ?>",
            "<?php if (\$fn_include = \$this->_include(\"\\1\")) include(\$fn_include); ?>",
            "<?php if (\$fn_include = \$this->_include(\"\\1\")) include(\$fn_include); ?>",
            "<?php if (\$fn_include = \$this->_load(\"\\1\")) include(\$fn_include); ?>",
            "<?php if (\$fn_include = \$this->_load(\"\\1\")) include(\$fn_include); ?>",
            "<?php \\1 ?>",
            "<?php \$rt_\\2 = \$this->list_tag(\"\\1 return=\\2\"); if (\$rt_\\2) extract(\$rt_\\2); \$count_\\2=dr_count(\$return_\\2); if (is_array(\$return_\\2)) { foreach (\$return_\\2 as \$key_\\2=>\$\\2) { \$is_first=\$key_\\2==0 ? 1 : 0;\$is_last=\$count_\\2==\$key_\\2+1 ? 1 : 0; ?>",
            "<?php \$rt = \$this->list_tag(\"\\1\"); if (\$rt) extract(\$rt); \$count=dr_count(\$return); if (is_array(\$return)) { foreach (\$return as \$key=>\$t) { \$is_first=\$key==0 ? 1 : 0;\$is_last=\$count==\$key+1 ? 1 : 0; ?>",
            "<?php } } ?>",
            "<?php if (\\1) { ?>",
            "<?php } else if (\\1) { ?>",
            "<?php } else { ?>",
            "<?php } ?>",
            "<?php if (is_array(\$\\1)) { \$count=dr_count(\$\\1);foreach (\$\\1 as \$\\2=>\$\\3) { ?>",
            "<?php if (is_array(\$\\1)) { \$count=dr_count(\$\\1);foreach (\$\\1 as \$\\2) { ?>",
            "<?php if (is_array(\$\\1)) { \$count=dr_count(\$\\1);foreach (\$\\1 as \$\\2=>\$\\3) { ?>",
            "<?php } } ?>",
            "<?php ",
            " ?>",
            " ",
        );

        // list标签别名
        foreach ($this->action as $name) {
            // 正则表达式匹配的模板标签
            $regex_array[] = '#{'.$name.'\s+(.+?)return=(.+?)\s?}#i';
            $regex_array[] = '#{'.$name.'\s+(.+?)\s?}#i';
            $regex_array[] = '#{\s?\/'.$name.'\s?}#i';
            // 替换直接变量输出
            $replace_array[] = "<?php \$list_return_\\2 = \$this->list_tag(\"action=".$name." \\1 return=\\2\"); if (\$list_return_\\2) extract(\$list_return_\\2, EXTR_OVERWRITE); \$count_\\2=dr_count(\$return_\\2); if (is_array(\$return_\\2)) { foreach (\$return_\\2 as \$key_\\2=>\$\\2) { \$is_first=\$key_\\2==0 ? 1 : 0;\$is_last=\$count_\\2==\$key_\\2+1 ? 1 : 0; ?>";
            $replace_array[] = "<?php \$list_return = \$this->list_tag(\"action=".$name." \\1\"); if (\$list_return) extract(\$list_return, EXTR_OVERWRITE); \$count=dr_count(\$return); if (is_array(\$return)) { foreach (\$return as \$key=>\$t) { \$is_first=\$key==0 ? 1 : 0;\$is_last=\$count==\$key+1 ? 1 : 0; ?>";
            $replace_array[] = "<?php } } ?>";
        }
        $view_content = preg_replace($regex_array, $replace_array, $view_content);

        // 兼容php5.5
        $view_content = preg_replace_callback("/_get_var\('(.*)'\)/Ui", 'php55_replace_cache_array', $view_content);
        $view_content = preg_replace_callback("/list_tag\(\"(.*)\"\)/Ui", 'php55_replace_array', $view_content);

        return $view_content;
    }

    // 替换cache标签中的单引号数组
    public function _replace_cache_array($string) {
        return "_get_var('" . preg_replace('#\[\'(\w+)\'\]#Ui', '.\\1', $string) . "')";
    }

    // 替换list标签中的单引号数组
    public function _replace_array($string) {
        return "list_tag(\"" . preg_replace('#\[\'(\w+)\'\]#Ui', '[\\1]', $string) . "\")";
    }

    // list 标签解析
    public function list_tag($_params) {

        if (!$this->ci) {
            return NULL;
        }

        $system = array(
            'num' => '', // 显示数量
            'page' => '', // 是否分页
            'catid' => '', // 栏目id，支持多id
            'field' => '', // 显示字段
            'order' => '', // 排序
            'table' => '', // 表名变量
            'join' => '', // 关联表名
            'on' => '', // 关联表条件
            'cache' => 3600, // 默认缓存时间
            'action' => '', // 动作标识
            'return' => '', // 返回变量
            'sbpage' => '', // 不按默认分页
            'module' => '', // 模型名称
            'keyword' => '', // 关键字
            'urlrule' => '', // 自定义分页规则
            'pagesize' => '', // 自定义分页数量
        );
        $param = $where = array();
        $params = explode(' ', $_params);
        $sysadj = array('IN', 'BEWTEEN', 'BETWEEN', 'LIKE', 'NOTIN', 'NOT', 'BW');
        foreach ($params as $t) {
            $var = substr($t, 0, strpos($t, '='));
            $val = substr($t, strpos($t, '=') + 1);
            if (!$var) {
                continue;
            }
            $val = defined($val) ? constant($val) : $val;
            if ($var == 'fid' && !$val) {
                continue;
            }
            if (isset($system[$var])) { // 系统参数，只能出现一次，不能添加修饰符
                $system[$var] = $val;
            } else {
                if (preg_match('/^([A-Z_]+)(.+)/', $var, $match)) { // 筛选修饰符参数
                    $_pre = explode('_', $match[1]);
                    $_adj = '';
                    foreach ($_pre as $p) {
                        in_array($p, $sysadj) && $_adj = $p;
                    }
                    $where[] = array(
                        'adj' => $_adj,
                        'name' => $match[2],
                        'value' => $val
                    );
                } else {
                    $where[] = array(
                        'adj' => '',
                        'name' => $var,
                        'value' => $val
                    );
                }
                $param[$var] = $val; // 用于特殊action
            }
        }

        // 替换order中的非法字符
        isset($system['order']) && $system['order'] && $system['order'] = str_ireplace(
            array('"', "'", ')', '(', ';', 'select', 'insert'),
            '',
            $system['order']
        );

        $action = $system['action'];
        // 当hits动作时，定位到moule动作
        $system['action'] == 'hits' && $system['action'] = 'module';
        $system['module'] = (string)$system['module'];

        // action
        switch ($system['action']) {

            case 'cache': // 系统缓存数据

                break;


            case 'category': // 栏目

                $i = 0;
                $return = array();
                foreach ($this->ci->category as $t) {
                    if ($system['num'] && $i >= $system['num']) {
                        break;
                    } elseif (!$t['show']) {
                        continue;
                    } elseif (isset($param['pid']) && $t['pid'] != (int)$param['pid']) {
                        continue;
                    } elseif (isset($param['mid']) && $t['mid'] != $param['mid']) {
                        continue;
                    } elseif (isset($param['tid']) && $t['tid'] != $param['tid']) {
                        continue;
                    } elseif (isset($param['child']) && $t['child'] != (int)$param['child']) {
                        continue;
                    } elseif (isset($param['letter']) && $t['letter'] != $param['letter']) {
                        continue;
                    } elseif (isset($param['id']) && !in_array($t['id'], explode(',', $param['id']))) {
                        continue;
                    } elseif (isset($system['more']) && !$system['more']) {
                        unset($t['field'], $t['setting']);
                    }
                    $t['url'] = dr_category_url($t);
                    $return[] = $t;
                    $i ++;
                }

                if (!$return) {
                    return $this->_return($system['return'], '没有匹配到内容');
                }

                return $this->_return($system['return'], $return, '');
                break;

            case 'linkage': // 联动菜单

                $linkage = $this->ci->get_cache('linkage-'.$param['code']);
                if (!$linkage) {
                    return $this->_return($system['return'], "联动菜单{$param['code']}不存在，请在后台更新缓存");
                }

                // 通过别名找id
                $ids = @array_flip($this->ci->get_cache('linkage-'.$system['site'].'-'.$param['code'].'-id'));
                if (isset($param['pid'])) {
                    if (is_numeric($param['pid'])) {
                        $pid = intval($param['pid']);
                    } else {
                        $pid = isset($ids[$param['pid']]) ? $ids[$param['pid']] : 0;
                        !$pid && is_numeric($param['pid']) && $this->ci->get_cache('linkage-'.$system['site'].'-'.$param['code'].'-id', $param['pid']) && $pid = intval($param['pid']);
                    }
                }

                $i = 0;
                $return = array();
                foreach ($linkage as $t) {
                    if ($system['num'] && $i >= $system['num']) {
                        break;
                    } elseif (isset($param['pid']) && $t['pid'] != $pid) {
                        continue;
                    } elseif (isset($param['id']) && !in_array($t['id'], explode(',', $param['id']))) {
                        continue;
                    }
                    $return[] = $t;
                    $i ++;
                }

                if (!$return && isset($param['pid'])) {
                    $rpid = isset($param['fid']) ? (int)$ids[$param['fid']] : (int)$linkage[$param['pid']]['pid'];
                    foreach ($linkage as $t) {
                        if ($t['pid'] == $rpid) {
                            if ($system['num'] && $i >= $system['num']) {
                                break;
                            }
                            if (isset($param['id']) && !in_array($t['id'], explode(',', $param['id']))) {
                                continue;
                            }
                            $return[] = $t;
                            $i ++;
                        }
                    }
                    if (!$return) {
                        return $this->_return($system['return'], '没有匹配到内容');
                    }
                }

                return $this->_return($system['return'], isset($param['call']) && $param['call'] ? @array_reverse($return) : $return, '');
                break;

            case 'related': // 相关文章

                $category = $this->ci->category;

                // 通过栏目找module
                if (!$system['module']) {
                    if (!$system['catid']) {
                        return $this->_return($system['return'], 'catid或者module参数不能为空');
                    }
                    $system['module'] = (string)$category[$system['catid']]['mid'];
                    if (!$system['module']) {
                        return $this->_return($system['return'], '栏目（'.$system['catid'].'）不是模块类型');
                    }
                }
                $cache_data = $this->ci->get_cache('content', $system['module']);
                if (!$cache_data) {
                    return $this->_return($system['return'], '模型（'.$system['module'].'）没有任何数据');
                }

                // 栏目筛选
                $catids = [];
                if ($system['catid']) {
                    if (strpos($system['catid'], ',') !== FALSE) {
                        $temp = @explode(',', $system['catid']);
                        if ($temp) {
                            $catids = array();
                            foreach ($temp as $i) {
                                $catids = $category[$i]['child'] ? array_merge($catids, $category[$i]['catids']) : array_merge($catids, array($i));
                            }
                        }
                        unset($temp);
                    } elseif ($category[$system['catid']]['child']) {
                        $catids = explode(',', $category[$system['catid']]['childids']);
                    } else {
                        $catids = [(int)$system['catid']];
                    }
                }

                $rt = [];
                $i = 1;
                foreach ($cache_data as $id => $t) {
                    if ($catids && !in_array($t['catid'], $catids)) {
                        continue;
                    }
                    if ($param['id'] && $param['id'] == $id) {
                        continue;
                    }
                    if ($param['tag']) {
                        $ck = 0;
                        $arr = explode(',', $param['tag']);
                        foreach ($arr as $a) {
                            if (strpos($t['title'], $a) !== false || strpos($t['keywords'], $a) !== false) {
                                $ck = 1;
                                break;
                            }
                        }
                        if (!$ck) {
                            break;
                        }
                    } else {
                        break;
                    }
                    if ($system['num'] && $i > $system['num']) {
                        break;
                    }
                    $t['url'] = dr_show_url($t);
                    $rt[] = $t;
                    $i++;
                }



                $total = count($rt);


                return $this->_return($system['return'], $rt, '', $total);

                break;
            case 'module': // 模型数据

                $category = $this->ci->category;

                // 通过栏目找module
                if (!$system['module']) {
                    if (!$system['catid']) {
                        return $this->_return($system['return'], 'catid或者module参数不能为空');
                    }
                    $system['module'] = (string)$category[$system['catid']]['mid'];
                    if (!$system['module']) {
                        return $this->_return($system['return'], '栏目（'.$system['catid'].'）不是模块类型');
                    }
                }
                $cache_data = $this->ci->get_cache('content', $system['module']);
                if (!$cache_data) {
                    return $this->_return($system['return'], '模型（'.$system['module'].'）没有任何数据');
                }

                // 栏目筛选
                $catids = [];
                if ($system['catid']) {
                    if (strpos($system['catid'], ',') !== FALSE) {
                        $temp = @explode(',', $system['catid']);
                        if ($temp) {
                            $catids = array();
                            foreach ($temp as $i) {
                                $catids = $category[$i]['child'] ? array_merge($catids, $category[$i]['catids']) : array_merge($catids, array($i));
                            }
                        }
                        unset($temp);
                    } elseif ($category[$system['catid']]['child']) {
                        $catids = explode(',', $category[$system['catid']]['childids']);
                    } else {
                        $catids = [(int)$system['catid']];
                    }
                }

                $rt = [];
                $i = 1;

                if ($system['order'] == 'rand') {
                    shuffle($cache_data);
                }

                foreach ($cache_data as $t) {
                    if ($catids && !in_array($t['catid'], $catids)) {
                        continue;
                    }
                    if ($system['num'] && $i > $system['num']) {
                        break;
                    }
                    $t['url'] = dr_show_url($t);
                    $rt[] = $t;
                    $i++;
                }



                $total = count($rt);
                $pages = '';

                if ($system['page']) {
                    $page = max(1, (int)$_GET['page']);
                    if (is_numeric($system['catid'])) {
                        $urlrule = SPACE_YULAN ? dr_category_url($category[$system['catid']], '[page]') : $category[$system['catid']]['urlrule'];
                        $pagesize = $system['pagesize'] ? (int)$system['pagesize'] : (int)$category[$system['catid']]['setting']['template']['pagesize'];
                    }
                    if ($system['sbpage'] || !$urlrule){
                        $urlrule = str_replace('[page]', '{page}', urldecode($system['urlrule']));
                        $pagesize = (int)$system['pagesize'];
                    }
                    $pagesize = $pagesize ? $pagesize : 10;
                    //
                    //$offset = ceil($total / $pagesize) * $page;
                    $star = ($page - 1) * $pagesize; // 开始数量

                    $i = 1;
                    $rt2 = [];
                    foreach ($rt as $j => $t) {
                        if ($star <= $j) {
                            if ($i > $pagesize) {
                                break;
                            }
                            $rt2[] = $t;
                            $i++;
                        }

                    }
                    $rt = $rt2;
                    $pages = $this->_get_pagination($urlrule, $pagesize, $total);
                }



                return $this->_return($system['return'], $rt, '', $total, $pages, $pagesize);
                break;

            default :
                return $this->_return($system['return'], 'list标签必须含有参数action或者action参数错误');
                break;
        }
    }



    /**
     * 分页
     */
    public function _get_pagination($url, $pagesize, $total) {

        require FCPATH.'page.php';

        $obj = new page();

        $config = array();
        if (is_file($this->_root.'page.php')) {
            include $this->_root.'page.php';
            $page = $config['pagination'];
        }

        $page['base_url'] = str_replace('[page]', '{page}', dr_url($url));
        $page['per_page'] = $pagesize;
        $page['total_rows'] = $total;
        $page['use_page_numbers'] = TRUE;
        $page['query_string_segment'] = 'page';

        $obj->initialize($page);

        return $obj->dr_links();
    }



    // list 返回
    public function _return($return, $data = NULL, $sql = NULL, $total = NULL, $pages = NULL, $pagesize = NULL) {

        $debug = $error = '';
        if ($data && !is_array($data)) {
            $error = $data;
            $data = NULL;
        }

        $debug = $sql.'<br>';

            // 错误信息格式化
        $error && $debug.= $error = '<div style="padding:10px;margin:10px;margin-top:20px;border:1px solid #ffbe7a;background:#fffced;color:red;font-weight:bold;">'.$error."</div>";

        $total = isset($total) ? $total : dr_count($data);
        $page = max(1, (int)$_GET['page']);
        $nums = $pagesize ? ceil($total/$pagesize) : 0;

        // 返回数据格式
        if ($return) {
            return array(
                'nums_'.$return => $nums,
                'page_'.$return => $page,
                'pages_'.$return => $pages,
                'error_'.$return => $error,
                'total_'.$return => $total,
                'return_'.$return => $data,
                'debug_'.$return => $debug,
                'pagesize_'.$return => $pagesize,
            );
        } else {
            return array(
                'nums' => $nums,
                'debug' => $debug,
                'page' => $page,
                'pages' => $pages,
                'error' => $error,
                'total' => $total,
                'return' => $data,
                'pagesize' => $pagesize,
            );
        }
    }



}

// 替换cache标签中的单引号数组 for php5.5
function php55_replace_cache_array($string) {
    return "_get_var('".preg_replace('#\[\'(\w+)\'\]#Ui', '.\\1', $string[1])."')";
}

// 替换list标签中的单引号数组
function php55_replace_array($string) {
    return "list_tag(\"".preg_replace('#\[\'(\w+)\'\]#Ui', '[\\1]', $string[1])."\")";
}

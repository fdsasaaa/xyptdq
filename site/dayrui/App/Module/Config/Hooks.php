<?php


/**
 * 模块首页地址
 * $dir 模块目录
 */
function dr_module_url($dir) {

    if (defined('MOD_DIR') && $dir == MOD_DIR) {
        return MODULE_URL;
    }

    return \Phpcmf\Service::L('cache')->get('module-'.dr_module_siteid().'-'.$dir, 'url');
}

function dr_module_category_data_field($cat, $field, $module) {
    if (!$cat['ismain']) {
        // 非主栏目继承上级
        $cat = dr_cat_value(
            $module['mid'],
            \Phpcmf\Service::L('category', 'module')->get_ismain_id($module['mid'], $cat)
        );
    }
    if ($cat) {
        if (isset($module['setting']['module_category_hide']) && $module['setting']['module_category_hide']) {
            if ($module['category_data_field']) {
                foreach ($module['category_data_field'] as $f => $v) {
                    if (!dr_in_array($f, $cat['field'])) {
                        $field[$f] = $v;
                    }
                }
            }
        } else {
            if ($cat['field']) {
                foreach ($cat['field'] as $f) {
                    if ($module['category_data_field'][$f]) {
                        $field[$f] = $module['category_data_field'][$f];
                    }
                }
            }
        }
    }
    return $field;
}
function dr_module_param($mid, $name) {

    if (!$mid) {
        return '';
    }

    return \Phpcmf\Service::L('cache')->get('module-'.dr_module_siteid().'-'.$mid, 'setting', 'param', $name);
}
// 获取所属站点id
function dr_module_siteid() {
    if (isset(XR_C()->content_model->siteid) && (XR_C()->content_model->siteid)) {
        return XR_C()->content_model->siteid;
    }
    return SITE_ID;
}

if (!function_exists('dr_is_double_search')) {
    // 判断搜索值是否是多重选择时的选中状态 1选中 0不选
    function dr_is_double_search($param, $value) {

        if (!$param) {
            return 0;
        }

        $arr = explode('|', $param);
        if (in_array($value, $arr)) {
            return 1;
        }

        return 0;
    }
}

if (!function_exists('dr_get_double_search')) {
    // 获取多重选择是的参数值
    function dr_get_double_search($param, $value) {

        if (!$param) {
            return $value;
        }

        $arr = explode('|', $param);
        if (in_array($value, $arr)) {
            // 如果存在，那么久移除他
            $arr = array_merge(array_diff($arr, array($value)));
        } else {
            // 没有就加上
            $arr[] = $value;
        }

        return $arr ? @implode('|', $arr) : '';
    }
}

// 获取内容的tags
function dr_get_content_tags($value) {

    if (is_array($value)) {
        return $value;
    } elseif (!$value) {
        return [];
    }

    $rt = [];
    $tag = explode(',', $value);
    foreach ($tag as $t) {
        $t = trim($t);
        if ($t) {
            // 读缓存
            if (dr_is_app('tag')) {
                $obj = \Phpcmf\Service::M('tag', 'tag');
                if (method_exists($obj, 'get_tag_url')) {
                    $url = $obj->get_tag_url($t);
                    if ($url) {
                        $rt[$t] = $url;
                    }
                }
            }
        }
    }

    return $rt;
}

// 获取内容的搜索词
function dr_get_content_kws($value, $mid = '') {

    if (is_array($value)) {
        return $value;
    } elseif (!$value) {
        return [];
    }

    $rt = [];
    $mid = $mid ? $mid : (defined('MOD_DIR') ? MOD_DIR : '');
    $tag = explode(',', $value);
    foreach ($tag as $t) {
        $t = trim($t);
        if ($t) {
            $rt[$t] = \Phpcmf\Service::L('router')->search_url([], 'keyword', $t, $mid);
        }
    }

    return $rt;
}


/**
 * 内容文章显示内链
 */
function dr_content_link($tags, $content, $num = 0, $blank = 1) {

    if (!$tags || !$content) {
        return $content;
    } elseif (!is_array($tags)) {
        return $content;
    }

    foreach ($tags as $name => $url) {
        if ($name && $url) {
            $content = @preg_replace(
                '\'(?!((<.*?)|(<a.*?)|(<strong.*?)))('.str_replace(["'", '-'], ["\'", '\-'], preg_quote($name)).')(?!(([^<>]*?)>)|([^>]*?</a>)|([^>]*?</strong>))\'si',
                '<a title="'.$name.'" href="'.$url.'"'.($blank ? ' target="_blank"' : '').'>'.$name.'</a>',
                $content,
                $num ? $num : -1
            );
        }
    }

    return $content;
}


// 内容加内链
function dr_neilian($content, $blank = 1, $num = 0) {

    if (!$content) {
        return '';
    }

    if (dr_is_app('tag')) {
        $obj = \Phpcmf\Service::M('tag', 'tag');
        if (method_exists($obj, 'neilian')) {
            return $obj->neilian($content, $blank, $num);
        }
    }

    return $content;
}

// 获取模块数据及自定义字段
function dr_mod_value(...$get) {

    if (empty($get)) {
        return '';
    }

    if (is_numeric($get[0]) && defined('MOD_DIR') && MOD_DIR) {
        // 值是栏目id时，表示当前模块
        $name = 'module-'.dr_module_siteid().'-'.MOD_DIR;
    } else {
        // 指定模块
        $name = strpos($get[0], '-') ? 'module-'.$get[0] : 'module-'.dr_module_siteid().'-'.$get[0];
        unset($get[0]);
    }

    $i = 0;
    $param = [];
    foreach ($get as $t) {
        if ($i == 0) {
            $param[] = $name;
        }
        $param[] = $t;
        $i = 1;
    }

    return call_user_func_array([\Phpcmf\Service::C(), 'get_cache'], $param);
}


// 获取栏目数据及自定义字段
function dr_page_value($id, $field, $site = SITE_ID) {

    if (empty($id)) {
        return '';
    }

    return \Phpcmf\Service::C()->get_cache('page-'.$site, 'data', $id, $field);
}

// 获取栏目数据及自定义字段
function dr_cat_value(...$get) {

    if (empty($get)) {
        return [];
    }

    $mid = '';
    if (is_numeric($get[0])) {
        // 值是栏目id时，表示当前模块
        if (defined('MOD_DIR') && MOD_DIR) {
            $mid = MOD_DIR;
            $name = 'module-'.dr_module_siteid().'-'.MOD_DIR;
        } else {
            $name = 'module-'.dr_module_siteid().'-share';
        }
    } else {
        // 指定模块
        $mid = $get[0] ? $get[0] : 'share';
        $name = strpos($mid, '-') ? 'module-'.$mid : 'module-'.dr_module_siteid().'-'.$mid;
        unset($get[0]);
    }

    $i = 0;
    $param = [];
    foreach ($get as $t) {
        if ($i == 0) {
            $param[] = $name;
            $param[] = 'category';
        }
        $param[] = $t;
        $i = 1;
    }

    $rt = call_user_func_array([\Phpcmf\Service::C(), 'get_cache'], $param);
    if (end($param) == 'url' && $rt) {
        $rt = dr_url_rel(dr_url_prefix($rt, $mid));
    }

    return $rt;
}

// 获取共享栏目数据及自定义字段
function dr_share_cat_value($id, $field='') {

    $get = func_get_args();
    if (empty($get)) {
        return [];
    }

    $i = 0;
    $param = [];
    foreach ($get as $t) {
        if ($i == 0) {
            $param[] = 'module-'.dr_module_siteid().'-share';
            $param[] = 'category';
        }
        $param[] = $t;
        $i = 1;
    }

    $rt = call_user_func_array(array(\Phpcmf\Service::C(), 'get_cache'), $param);

    return $field == 'url' && $rt ? dr_url_rel(dr_url_prefix($rt)) : $rt;
}


/**
 * 模块栏目面包屑导航
 *
 * @param   intval  $catid  栏目id
 * @param   string  $symbol 面包屑间隔符号
 * @param   string  $url    是否显示URL
 * @param   string  $html   格式替换
 * @return  string
 */
function dr_catpos($catid, $symbol = ' > ', $url = true, $html= '', $dirname = 'MOD_DIR', $url_call_func = '') {

    if (!$catid) {
        return '';
    }

    $mid = $dirname == 'MOD_DIR' && defined('MOD_DIR') && MOD_DIR ? MOD_DIR : (!$dirname || $dirname == 'MOD_DIR' ? 'share' : $dirname);
    $cat = \Phpcmf\Service::L('cache')->get('module-'.dr_module_siteid().'-'.$mid, 'category');
    if (!isset($cat[$catid])) {
        return '';
    }

    $name = [];
    $array = explode(',', $cat[$catid]['pids']);
    $array[] = $catid;
    foreach ($array as $id) {
        if ($id && $cat[$id]) {
            if ($url_call_func && function_exists($url_call_func)) {
                $murl = $url_call_func($cat[$id]);
            } else {
                $murl = dr_url_rel(dr_url_prefix($cat[$id]['url'], $mid));
                //$murl = dr_url_prefix($cat[$id]['url'], MOD_DIR, dr_module_siteid(), \Phpcmf\Service::IS_MOBILE_TPL())
            }
            $name[] = $url ? ($html ? str_replace(['[url]', '[name]'], [$murl, $cat[$id]['name']], $html): "<a href=\"{$murl}\">{$cat[$id]['name']}</a>") : $cat[$id]['name'];
        }
    }

    return implode($symbol, array_unique($name));
}


// 打赏支付
function dr_donation($id, $title = '', $dir = '', $remove_div  = 1) {
    if (!dr_is_app('pay')) {
        return '没有安装「支付系统」插件';
    }
    !$dir && $dir = defined('MOD_DIR') ? MOD_DIR : 'share';
    return \Phpcmf\Service::M('Pay', 'pay')->payform('my-shang_buy-'.$id.'_'.$dir.'-'.dr_module_siteid(), 0, $title, '', $remove_div);
}

// 是否存在收藏夹中 1收藏了 2没有收藏
function dr_is_favorite($dir, $id, $uid = 0) {

    !$uid && $uid = \Phpcmf\Service::C()->uid;

    if (!$uid) {
        return 0;
    } elseif (!$dir) {
        return 0;
    }

    return \Phpcmf\Service::M()->db->table(dr_module_table_prefix($dir).'_favorite')->where('uid', $uid)->where('cid', $id)->countAllResults();
}


/**
 * 模块内容阅读量显示js
 *
 * @param   intval  $id
 * @return  string
 */
if (!function_exists('dr_show_hits')) {
    function dr_show_hits($id, $dom = "", $dir = 'MOD_DIR') {
        $is = $dom;
        !$dom && $dom = "dr_show_hits_{$id}";
        $html = $is ? "" : "<span class=\"{$dom}\">0</span>";
        if (defined('MODULE_MYSHOW')) {
            return $html;
        }
        $dir = $dir == 'MOD_DIR' && defined('MOD_DIR') && MOD_DIR ? MOD_DIR : $dir;
        $rt = "$(\".{$dom}\").html(data.msg);";
        if ($is) {
            $rt.= "$(\"#{$dom}\").html(data.msg);";
        }
        return $html."<script type=\"text/javascript\">var apiurl=\"".dr_web_prefix("index.php?s=api&c=module&siteid=".dr_module_siteid()."&app=".$dir)."\"; $.ajax({ type: \"GET\", url:apiurl+\"&m=hits&id={$id}\", dataType: \"jsonp\", success: function(data){ if (data.code) { ".$rt." } else { dr_tips(0, data.msg); } } }); </script>";
    }
}


/**
 * 栏目下级或者同级栏目
 * $data 整个栏目数组
 * $catid 当前栏目id
 */
function dr_related_cat($data, $catid) {

    if (!$data) {
        return [[], []];
    }

    $my = $data[$catid];
    $related = $parent = [];

    if ($my['child']) {
        // 当存在子栏目时就显示下级子栏目
        $parent = $my['pid'] ? $data[$my['pid']] : $my;
        foreach ($data as $t) {
            if (!$t['show']) {
                continue;
            }
            if ($t['pid'] == $my['id']) {
                $t['url'] = dr_url_prefix($t['url'], defined('MOD_DIR') ? MOD_DIR : '');
                $related[$t['id']] = $t;
            }
        }
    } elseif ($my['pid']) {
        // 当属于子栏目时就显示同级别栏目
        foreach ($data as $t) {
            if (!$t['show']) {
                continue;
            }
            if ($t['pid'] == $my['pid']) {
                $t['url'] = dr_url_prefix($t['url'], defined('MOD_DIR') ? MOD_DIR : '');
                $related[$t['id']] = $t;
                $parent = $data[$t['pid']];
            }
        }
    } else {
        // 显示顶级栏目
        if (!$data) {
            return [[], []];
        }
        $parent = $my;
        foreach ($data as $t) {
            if (!$t['show']) {
                continue;
            }
            if ($t['pid'] == 0) {
                $t['url'] = dr_url_prefix($t['url'], defined('MOD_DIR') ? MOD_DIR : '');
                $related[$t['id']] = $t;
            }
        }
    }

    $parent && $parent['url'] = dr_url_prefix($parent['url'], defined('MOD_DIR') ? MOD_DIR : '');

    return [$parent, $related];
}

/**
 * 模块栏目层次关系
 *
 * @param   array   $mod
 * @param   array   $cat
 * @param   string  $symbol
 */
function dr_get_cat_pname($mod, $catid, $symbol = '_') {

    $cat = $mod['category'][$catid];

    if (!$cat['pids']) {
        return $cat['name'];
    }

    $name = [];
    $array = explode(',', $cat['pids']);

    foreach ($array as $id) {
        if ($id && $mod['category'][$id]) {
            $name[] = $mod['category'][$id]['name'];
        }
    }

    $name[] = $cat['name'];

    $name = array_unique($name);

    krsort($name);

    return implode($symbol, $name);
}



/**
 * url转为相对路径
 */
if (!function_exists('dr_url_rel')) {

    /**
     * url转为相对路径
     */
    function dr_url_rel($url, $prefix = '') {

        if ((IS_API_HTTP && (!defined('SYS_API_REL') || !SYS_API_REL)) || IS_ADMIN) {
            return $url;
        } elseif (defined('SYS_URL_REL') && SYS_URL_REL) {
            $surl = FC_NOW_HOST;
            if (defined('SC_HTML_FILE') && SITE_IS_MOBILE_HTML
                && \Phpcmf\Service::V()->_is_mobile
                && strpos(SITE_MURL, SITE_URL) === false
            ) {
                // 静态生成，移动端域名模式下
                $surl = SITE_MURL;
            }
            $url = str_replace($surl, '/', $url);
            if (IS_DEV && strpos($url, 'http') === 0) {
                $url.= '#站外域名不能转为相对路径（本提示信息关闭开发者模式时不显示）';
            }
            $prefix && $url = str_replace($prefix, '/', $url);
        }

        return $url;
    }
}


/**
 * 内容中的转为相对路径
 */
if (!function_exists('dr_text_rel')) {


    /**
     * 内容中的转为相对路径
     */
    function dr_text_rel($text, $prefix = '') {

        if ((IS_API_HTTP && (!defined('SYS_API_REL') || !SYS_API_REL)) || IS_ADMIN) {
            return $text;
        } elseif (defined('SYS_URL_REL') && SYS_URL_REL) {
            $surl = FC_NOW_HOST;
            if (defined('SC_HTML_FILE') && SITE_IS_MOBILE_HTML
                && \Phpcmf\Service::V()->_is_mobile
                && strpos(SITE_MURL, SITE_URL) === false
            ) {
                // 静态生成，移动端域名模式下
                $surl = SITE_MURL;
            }
            $text = str_replace('href="'.$surl, 'href="/', $text);
            $text = str_replace('href=\''.$surl, 'href="/', $text);
            $text = str_replace('src="'.$surl, 'src="/', $text);
            $text = str_replace('src=\''.$surl, 'src="/', $text);
            if ($prefix) {
                $surl = $prefix;
                $text = str_replace('href="'.$surl, 'href="/', $text);
                $text = str_replace('href=\''.$surl, 'href="/', $text);
                $text = str_replace('src="'.$surl, 'src="/', $text);
                $text = str_replace('src=\''.$surl, 'src="/', $text);
            }
        }

        return $text;
    }
}


/**
 * 模块栏目URL地址
 *
 * @param    array $mod
 * @param    array $data
 * @param    intval $page
 * @return    string
 */
function dr_module_category_url($mod, $data, $page = 0, $fid = 0) {

    if (!$mod) {
        return '栏目所属模块不存在';
    } elseif (!$data) {
        return '栏目数据不存在';
    }

    // 是否分页
    $page && $data['page'] = $page = is_numeric($page) ? max((int)$page, 1) : $page;
    !$page && $page = 1;
    $is_page = $page > 1 || strpos($page, 'page') !== false;

    // 获取自定义URL
    $url = '';
    $rule = isset($data['setting']['urlrule']) ? \Phpcmf\Service::L('cache')->get('urlrule', (int)$data['setting']['urlrule'], 'value') : 0;
    if ($is_page) {
        if (isset($data['myurl_page']) && $data['myurl_page']) {
            $url = ltrim($data['myurl_page'], '/');
            return \Phpcmf\Service::L('router')->get_url_value($data, $url, \Phpcmf\Service::L('router')->url_prefix('rewrite', $mod, $data, $fid));
        } elseif ($rule && $rule['list_page']) {
            $url = ltrim($rule['list_page'], '/');
        }
    } else {
        if (isset($data['myurl']) && $data['myurl']) {
            $url = ltrim($data['myurl'], '/');
            return \Phpcmf\Service::L('router')->get_url_value($data, $url, \Phpcmf\Service::L('router')->url_prefix('rewrite', $mod, $data, $fid));
        } elseif ($rule && $rule['list']) {
            $url = ltrim($rule['list'], '/');
        }
    }

    if ($url) {
        // URL模式为自定义，且已经设置规则
        $data['fid'] = $fid;
        $data['modname'] = $mod['share'] ? '共享栏目不能使用modname标签' : $mod['dirname'];
        $data['pdirname'].= $data['dirname'];
        $data['pdirname'] = str_replace('/', $rule['catjoin'], $data['pdirname']);
        $data['otdirname'] = $data['opdirname'] = $data['dirname'];
        if ($data['pid']) {
            $pcat = dr_cat_value($mod['mid'], $data['pid']);
            if ($pcat) {
                $data['opdirname'] = $pcat['dirname'];
            }
        }
        if ($data['topid']) {
            $pcat = dr_cat_value($mod['mid'], $data['topid']);
            if ($pcat) {
                $data['otdirname'] = $pcat['dirname'];
            }
        }
        return \Phpcmf\Service::L('router')->get_url_value($data, $url, \Phpcmf\Service::L('router')->url_prefix('rewrite', $mod, $data, $fid));
    }

    return \Phpcmf\Service::L('router')->url_prefix('module_php', $mod, $data, $fid) . 'c=category&id=' . (isset($data['id']) ? $data['id'] : 0) . ($is_page ? '&page=' . $page : '');
}

/**
 * 模块内容URL地址
 *
 * @param    array $mod
 * @param    array $data
 * @param    mod $page
 * @return    string
 */
function dr_module_show_url($mod, $data, $page = 0) {

    if (!$mod) {
        return 'mod参数不存在';
    } elseif (!$data) {
        return 'data参数不完整';
    }

    $cat = dr_cat_value($mod['mid'], $data['catid']);

    $page && $data['page'] = $page = is_numeric($page) ? max((int)$page, 1) : $page;
    !$page && $page = 1;
    $is_page = $page > 1 || strpos($page, 'page') !== false;

    $url = '';
    $rule = \Phpcmf\Service::L('cache')->get('urlrule', (int)$cat['setting']['urlrule'], 'value');
    if ($is_page) {
        if (isset($data['myurl_page']) && $data['myurl_page']) {
            $url = ltrim($data['myurl_page'], '/');
            return \Phpcmf\Service::L('router')->get_url_value($data, $url, \Phpcmf\Service::L('router')->url_prefix('rewrite', $mod, $cat));
        } elseif ($rule && $rule['show_page']) {
            $url = ltrim($rule['show_page'], '/');
        }
    } else {
        if (isset($data['myurl']) && $data['myurl']) {
            $url = ltrim($data['myurl'], '/');
            return \Phpcmf\Service::L('router')->get_url_value($data, $url, \Phpcmf\Service::L('router')->url_prefix('rewrite', $mod, $cat));
        } elseif ($rule && $rule['show']) {
            $url = ltrim($rule['show'], '/');
        }
    }

    if ($url) {
        // URL模式为自定义，且已经设置规则
        $data['cat'] = $cat;
        $data['modname'] = $mod['dirname'];
        $cat['pdirname'].= $cat['dirname'];
        $data['dirname'] = $cat['dirname'];
        $inputtime = isset($data['_inputtime']) ? $data['_inputtime'] : $data['inputtime'];
        $data['y'] = date('Y', $inputtime);
        $data['yy'] = date('y', $inputtime);
        $data['m'] = date('m', $inputtime);
        $data['d'] = date('d', $inputtime);
        $data['pdirname'] = str_replace('/', $rule['catjoin'], $cat['pdirname']);
        $data['otdirname'] = $data['opdirname'] = $cat['dirname'];
        if ($cat['pid']) {
            $pcat = dr_cat_value($mod['mid'], $cat['pid']);
            if ($pcat) {
                $data['opdirname'] = $pcat['dirname'];
            }
        }
        if ($cat['topid']) {
            $pcat = dr_cat_value($mod['mid'], $cat['topid']);
            if ($pcat) {
                $data['otdirname'] = $pcat['dirname'];
            }
        }
        $data['url'] = \Phpcmf\Service::L('router')->get_url_value($data, $url, \Phpcmf\Service::L('router')->url_prefix('rewrite', $mod, $cat));
    } else {
        $data['url'] = \Phpcmf\Service::L('router')->url_prefix('module_php', $mod, $cat) . 'c=show&id=' . $data['id'] . ($is_page ? '&page=' . $page : '');
    }

    // 挂钩点 模块内容url地址获取
    $rt = \Phpcmf\Hooks::trigger_callback('module_update_url', $data);
    if ($rt && isset($rt['code']) && $rt['code']) {
        $data['url'] = $rt['data'];
    }

    return $data['url'];
}
// 模块URL
function dr_module_index_url($mod, $sid) {

    // 绑定域名的情况下
    if ($mod['site'][$sid]['domain']) {
        return dr_http_prefix($mod['site'][$sid]['domain']) . '/';
    }

    // 自定义规则的情况下
    $rule = \Phpcmf\Service::L('cache')->get('urlrule', (int)$mod['urlrule'], 'value', 'module');
    if ($rule) {
        return dr_web_prefix(str_replace('{modname}', $mod['dirname'], $rule));
    }

    return dr_web_prefix('index.php?s=' . $mod['dirname']);
}
/**
 * 搜索url组合
 *
 * @param    array $params 搜索参数数组
 * @param    string|array $name 当前参数名称
 * @param    string|array $value 当前参数值
 * @param    string $mid 强制定位到模块
 * @param    string $fid 指定fid
 * @return    string
 */
function dr_module_search_url($params = [], $name = '', $value = '', $mid = '', $fid = SITE_FID) {


    // 模块目录识别
    defined('MOD_DIR') && MOD_DIR && $dir = MOD_DIR;
    $mid && $dir = $mid;

    $mod = \Phpcmf\Service::L('cache')->get('module-' . dr_module_siteid() . '-' . $dir);
    if (!$mod) {
        return '模块[' . $dir . ']缓存不存在';
    }

    if ($name) {
        if (is_array($name)) {
            foreach ($name as $i => $_name) {
                if (isset($value[$i]) && strlen((string)$value[$i])) {
                    $params[$_name] = $value[$i];
                } else {
                    unset($params[$_name]);
                }
            }
        } else {
            if (strlen((string)$value)) {
                $params[$name] = $value;
            } else {
                unset($params[$name]);
            }
        }
    }

    if (is_array($params)) {
        foreach ($params as $i => $t) {
            if (strlen((string)$t) == 0) {
                unset($params[$i]);
            }
        }
    }

    $rule = \Phpcmf\Service::L('cache')->get('urlrule', (int)$mod['urlrule'], 'value');
    if ($rule && $rule['search']) {
        $fid && $data['fid'] = $fid;
        $data['modname'] = $mod['dirname'];
        $data['param'] = dr_search_rewrite_encode($params, $mod['setting']['search']);
        if ($params && !$data['param']) {
            log_message('debug', '模块['.$mod['dirname'].']无法通过[搜索参数字符串规则]获得参数');
        }
        $url = ltrim($data['param'] ? $rule['search_page'] : $rule['search'], '/');
        return dr_url_rel(dr_url_prefix(\Phpcmf\Service::L('router')->get_url_value($data, $url, \Phpcmf\Service::L('router')->url_prefix('rewrite', $mod)), $mod['dirname']));
    } else {
        return dr_url_rel(dr_url_prefix(\Phpcmf\Service::L('router')->url_prefix('php', $mod, [], $fid) . trim('c=search&' . (is_array($params) ? http_build_query($params) : ''), '&'), $mod['dirname']));
    }
}


function dr_module_checktitle() {
    // 获取参数
    $id = (int)\Phpcmf\Service::L('input')->get('id');
    $title = dr_safe_replace(htmlspecialchars((string)\Phpcmf\Service::L('input')->get('title')));
    $module = dr_safe_filename(\Phpcmf\Service::L('input')->get('module'));
    $cache = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$module);

    // 判断参数
    if (!$title || !$module || !$cache) {
        exit('');
    }

    // 判断是否重复存在
    if (\Phpcmf\Service::M()->db->table(dr_module_table_prefix($module))->where('id<>'.$id)->where('title', $title)->countAllResults()) {
        exit(dr_lang('已经有相同的%s存在', isset($cache['field']['title']['name']) ? $cache['field']['title']['name'] : dr_lang('主题')));
    }

    exit('');
}

function dr_module_api_search() {

    $dir = dr_safe_filename(\Phpcmf\Service::L('input')->get('dir'));
    if (!$dir) {
        \Phpcmf\Service::C()->_msg(0, dr_lang('模块参数不能为空'));
    } elseif (!dr_is_module($dir)) {
        \Phpcmf\Service::C()->goto_404_page(dr_lang('模块[%s]未安装', $dir));
    }

    $get = \Phpcmf\Service::L('input')->get();
    $cache = \Phpcmf\Service::L('cache')->get('module-'.SITE_ID.'-'.$dir);
    $param = [];
    foreach ($get as $key => $value) {
        if ($cache['field'] && isset($cache['field'][$key])) {
            $param[$key] = $value;
        }
    }

    // 跳转url
    dr_redirect(\Phpcmf\Service::L('Router')->search_url(
        $param,
        'keyword',
        dr_safe_replace(\Phpcmf\Service::L('input')->get('keyword')),
        $dir
    ));
}
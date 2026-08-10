<?php
/**
 * 迅睿工具箱
 */

header('Content-Type: text/html; charset=utf-8');
error_reporting(E_ALL ^ E_NOTICE ^ E_WARNING ^ E_STRICT);

if (phpversion() < '7.1')
{
    exit("PHP版本不能低于7.1，当前PHP版本是: " . phpversion());
}

define('WEBPATH', dirname(__FILE__).'/');
define('ROOTPATH', dirname(dirname(__FILE__)).'/');

if (is_file(ROOTPATH.'config/database.php')) {
    define('WRITEPATH',ROOTPATH.'cache/');
    define('CONFIGPATH',ROOTPATH.'config/');
} else {
    $web = dirname(dirname(dirname(__FILE__)));
    if (!is_file($web.'/config/database.php')) {
        $web = (dirname(dirname(__FILE__)));
        if (!is_file($web.'/config/database.php')) {
            $web = ((dirname(__FILE__)));
            if (!is_file($web.'/config/database.php')) {
                exit('无法找到数据库配置文件：'.ROOTPATH.'config/database.php');
            }
        }
    }
    define('WRITEPATH',$web.'/cache/');
    define('CONFIGPATH',$web.'/config/');
}

define('FCPATH', WEBPATH.'pcode/');
define('THEME_PATH', '/static/');
define('CMF_UPDATE_TIME', '');
define('SITE_URL', '/tool/');
define('LANG_PATH', '/api/language/zh-cn/'); // 语言包

define('TOOL_VERSION', '2.0');

// 是否来自ajax提交
define('IS_AJAX', (!empty($_SERVER['HTTP_X_REQUESTED_WITH']) && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) === 'xmlhttprequest'));
// 是否来自post提交
define('IS_POST', isset($_POST) && count($_POST) ? TRUE : FALSE);

define('IS_AJAX_POST', IS_POST);
// 当前系统时间戳
define('SYS_TIME', $_SERVER['REQUEST_TIME'] ? $_SERVER['REQUEST_TIME'] : time());

define('BASEPATH', true);
define('IS_ADMIN', 0);

define('SELF', pathinfo(__FILE__, PATHINFO_BASENAME));

// 正常访问模式
// 当前URL
$url = 'http';
if ((isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] == 'on')
    || (isset($_SERVER['SERVER_PORT']) && $_SERVER['SERVER_PORT'] == '443')
    || (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https')
    || (isset($_SERVER['HTTP_FROM_HTTPS']) && $_SERVER['HTTP_FROM_HTTPS'] == 'on')
    || (!empty($_SERVER['HTTP_FRONT_END_HTTPS']) && strtolower($_SERVER['HTTP_FRONT_END_HTTPS']) != 'off')
) {
    $url.= 's';
}
$host = strtolower($_SERVER['HTTP_HOST']);
if (strpos($host, ':') !== false) {
    list($nhost, $port) = explode(':', $host);
    if ($port == 80) {
        $host = $nhost; // 排除80端口
    }
}
$url.= '://'.$host;
define('FC_NOW_URL', $url.($_SERVER['REQUEST_URI'] ? $_SERVER['REQUEST_URI'] : $_SERVER['PHP_SELF']));
define('FC_NOW_HOST', $url.'/'); // 域名部分
define('DOMAIN_NAME', $host); // 当前域名

require FCPATH.'template.php';

$class = dr_safe_filename($_GET['c']);
if (!$class) {
    $class = 'home';
}

$function = dr_safe_filename($_GET['m']);
!$function && $function= 'index';

if (is_file(FCPATH.''.$class.'.php')) {
    require FCPATH.''.$class.'.php';
    $app = new $class();
    $app->$function();
} else {
    exit('控制器'.$class.'.php'.'不存在');
}


class Xunruicms {

    private $file;
    private $space = 32;
    private $header;
    private static $instance;

    public function __construct()
    {
        self::$instance =& $this;

        $this->template = new template();
        $this->template->ci = $this;



        $this->template->assign([
            'meta_title' => '数据备份工具箱',
            'menu' => [
                'index' => '导出数据',
                'after' => '导入数据',
                'error' => '导入时错误修复',
            ],
        ]);
    }

    /**
     * 配置文件
     *
     * @param	string	$file	文件绝对地址
     * @param	string	$name	文件备注名称
     * @return	object
     */
    public function file($file, $name = '', $space = 32) {
        $this->file = $file;
        $this->space = $space;
        $this->header = '<?php'.PHP_EOL.PHP_EOL.
            'if (!defined(\'BASEPATH\')) exit(\'No direct script access allowed\');'.PHP_EOL.PHP_EOL.
            '/**'.PHP_EOL.
            ' * '.$name.PHP_EOL.
            ' */'.PHP_EOL.PHP_EOL
        ;
        return $this;
    }

    /**
     * 生成require N维数组文件
     *
     * @param	array	data
     * @return	int
     */
    public function to_require($data) {

        if (!is_array($data)) {
            $data = [];
        }

        $body = $this->header.'return ';
        $body .= str_replace(array('  ', ' 
    '), array('    ', ' '), var_export($data, TRUE));
        $body .= ';';
        !is_dir(dirname($this->file)) && dr_mkdirs(dirname($this->file));

        // 重置Zend OPcache
        function_exists('opcache_reset') && opcache_reset();

        return @file_put_contents($this->file, $body, LOCK_EX);
    }

    public function post($name, $b=null) {
        return isset($_POST[$name]) ? $_POST[$name] : '';
    }

    public function get($name, $b=null) {
        return isset($_GET[$name]) ? $_GET[$name] : '';
    }

    public static function &get_instance()
    {
        return self::$instance;
    }


    /**
     * 统一返回json格式并退出程序
     */
    public function _json($code, $msg, $data = array()){

        echo json_encode(dr_return_data($code, $msg, $data));exit;
    }

    public function _msg($code, $msg, $url = '', $time = 0) {

        // 返回的钩子
        $rt = [
            'msg' => $msg,
            'url' => $url,
            'time' => $time,
            'mark' => $code,
            'code' => $code,
            'meta_title' => '提示信息'
        ];

        $this->template->assign($rt);
        $this->template->display('msg.html');exit();
    }
}

function dr_dir_delete($path, $del_dir = FALSE, $htdocs = FALSE, $_level = 0)
{
    // Trim the trailing slash
    $path = rtrim($path, '/\\');

    if ( ! $current_dir = @opendir($path))
    {
        return FALSE;
    }

    while (FALSE !== ($filename = @readdir($current_dir)))
    {
        if ($filename !== '.' && $filename !== '..')
        {
            $filepath = $path.DIRECTORY_SEPARATOR.$filename;

            if (is_dir($filepath) && $filename[0] !== '.' && ! is_link($filepath))
            {
                dr_dir_delete($filepath, $del_dir, $htdocs, $_level + 1);
            } else {
                unlink($filepath);
            }
        }
    }

    closedir($current_dir);
    $_level > 0  && rmdir($path); // 删除子目录

    return $del_dir && $_level == 0 ? rmdir($path) : TRUE;
}
/**
 * 文件扫描
 *
 * @param   string  $source_dir     Path to source
 * @param   int $directory_depth    Depth of directories to traverse
 *                      (0 = fully recursive, 1 = current dir, etc)
 * @param   bool    $hidden         Whether to show hidden files
 * @return  array
 */
function dr_file_map($source_dir) {

    if ($fp = opendir($source_dir)) {

        $filedata = [];
        $source_dir = rtrim($source_dir, DIRECTORY_SEPARATOR).DIRECTORY_SEPARATOR;

        while (FALSE !== ($file = readdir($fp))) {
            if ($file === '.' OR $file === '..'
                OR $file[0] === '.'
                OR !is_file($source_dir.$file)) {
                continue;
            }
            $filedata[] = $file;
        }
        closedir($fp);
        return $filedata;
    }

    return FALSE;
}
// php 5.5 以上版本的正则替换方法
class php5replace {

    private $data;

    public function __construct($data) {
        $this->data = $data;
    }

    // 替换常量值 for php5.5
    public function php55_replace_var($value) {
        $v = '';
        @eval('$v = '.$value[1].';');
        return $v;
    }

    // 替换数组变量值 for php5.5
    public function php55_replace_data($value) {
        return $this->data[$value[1]];
    }

    // 替换函数值 for php5.5
    public function php55_replace_function($value) {

        if (function_exists($value[1])) {
            if ($value[2] == '$data') {
                $param = $this->data;
            } else {
                $param = $value[2];
            }
            return call_user_func_array($value[1], is_array($param) ? $param : @explode(',', $param));
        }

        return $value[0];
    }

}
// 兼容统计
function dr_count($array_or_countable, $mode = COUNT_NORMAL){
    return is_array($array_or_countable) || is_object($array_or_countable) ? count($array_or_countable, $mode) : 0;
}
/**
 * 将字符串转换为数组
 *
 * @param   string  $data   字符串
 * @return  array
 */
function dr_string2array($data) {

    if (is_array($data)) {
        return $data;
    } elseif (!$data) {
        return [];
    }

    $rt = json_decode($data, true);
    if ($rt) {
        return $rt;
    }

    return unserialize(stripslashes($data));
}
/**
 * 递归创建目录
 *
 * @param   string  $dir    目录名称
 * @return  bool|void
 */
function dr_mkdirs($dir, $null = true) {

    if (!$dir) {
        return FALSE;
    }

    if (!is_dir($dir)) {
        dr_mkdirs(dirname($dir));
        if (!is_dir($dir)) {
            mkdir($dir, 0777, true);
        }
    }
}
function show_error($msg) {
    exit("<!DOCTYPE html><html lang=\"zh-cn\"><head><meta charset=\"utf-8\"><title>系统错误</title><style>        div.logo {            height: 200px;            width: 155px;            display: inline-block;            opacity: 0.08;            position: absolute;            top: 2rem;            left: 50%;            margin-left: -73px;        }        body {            height: 100%;            background: #fafafa;            font-family: \"Helvetica Neue\", Helvetica, Arial, sans-serif;            color: #777;            font-weight: 300;        }        h1 {            font-weight: lighter;            letter-spacing: 0.8;            font-size: 3rem;            margin-top: 0;            margin-bottom: 0;            color: #222;        }        .wrap {            max-width: 1024px;            margin: 5rem auto;            padding: 2rem;            background: #fff;            text-align: center;            border: 1px solid #efefef;            border-radius: 0.5rem;            position: relative;        }        pre {            white-space: normal;            margin-top: 1.5rem;        }        code {            background: #fafafa;            border: 1px solid #efefef;            padding: 0.5rem 1rem;            border-radius: 5px;            display: block;        }        p {            margin-top: 1.5rem;        }        .footer {            margin-top: 2rem;            border-top: 1px solid #efefef;            padding: 1em 2em 0 2em;            font-size: 85%;            color: #999;        }        a:active,        a:link,        a:visited {            color: #dd4814;        }</style></head><body><div class=\"wrap\"><p>{$msg}</p>    {$url}</div></body></html>");
}
/**
 * 安全过滤文件及目录名称函数
 */
function dr_safe_filename($string) {
    return str_replace(
        ['..', "/", '\\', ' ', '<', '>', "{", '}', ';', ':', '[', ']', '\'', '"', '*', '?'],
        '',
        (string)$string
    );
}
function dr_redirect($url = '', $method = 'auto', $code = NULL) {

    switch ($method) {
        case 'refresh':
            header('Refresh:0;url='.$url);
            break;
        default:
            header('Location: '.$url, TRUE, $code);
            break;
    }
    exit;
}
/**
 * 将数组转换为字符串
 *
 * @param   array   $data   数组
 * @return  string
 */
function dr_array2string($data) {
    return $data ? json_encode($data, JSON_UNESCAPED_UNICODE) : '';
}
/**
 * 数据返回统一格式
 */
function dr_return_data($code, $msg = '', $data = array()) {
    return array(
        'code' => $code,
        'msg' => $msg,
        'data' => $data,
    );
}

/**
 * 多语言输出
 */
function dr_lang(...$param) {

    if (empty($param)) {
        return null;
    }

    // 取第一个作为语言名称
    $string = $param[0];
    unset($param[0]);

    return $string;
}

/**
 * 当前URL
 */
function dr_now_url() {

    $pageURL = '';
    $pageURL.= $_SERVER['REQUEST_URI'] ? $_SERVER['REQUEST_URI'] : $_SERVER['PHP_SELF'];

    return $pageURL;
}

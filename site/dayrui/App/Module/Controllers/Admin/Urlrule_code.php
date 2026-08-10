<?php namespace Phpcmf\Controllers\Admin;

class Urlrule_code extends \Phpcmf\App
{

    public function index() {

        $domain = [];
        list($module, $site) = \Phpcmf\Service::M('Site')->domain();
        $domain[$site['site_domain']] = dr_lang('本站电脑域名');
        $site['mobile_domain'] && $domain[$site['mobile_domain']] = dr_lang('本站手机域名');
        if ($module) {
            foreach ($module as $dir => $t) {
                if ($site['module_'.$dir]) {
                    $domain[$site['module_'.$dir]] = dr_lang('%s电脑域名', $t['name']);
                }
                if ($site['module_mobile_'.$dir]) {
                    $domain[$site['module_mobile_'.$dir]] = dr_lang('%s手机域名', $t['name']);
                }
            }
        }

        $site = \Phpcmf\Service::M('Site')->config(SITE_ID);
        if ($site['client']) {
            foreach ($site['client'] as $t) {
                if ($t['domain']) {
                    $domain[$t['domain']] = dr_lang('%s终端域名', $t['name']);
                }
            }
        }
        if (strpos($site['config']['SITE_DOMAIN'], '/') !== false) {
            list($a, $b) = explode('/', $site['config']['SITE_DOMAIN']);
            $root = '/'.$b;
        } else {
            $root = '';
        }
        $server = strtolower($_SERVER['SERVER_SOFTWARE']);
        if (strpos($server, 'apache') !== FALSE) {
            $name = 'Apache';
            $note = '<font color=red><b>将以下内容保存为.htaccess文件，放到每个域名所绑定的根目录</b></font>';
            $code = '';

            // 子目录
            $code.= '###当存在多个子目录格式的域名时，需要多写几组RewriteBase标签：RewriteBase /目录/ '.PHP_EOL;
            if (isset($site['mobile']['mode']) && $site['mobile']['mode'] && $site['mobile']['dirname']) {
                $code.= 'RewriteEngine On'.PHP_EOL.PHP_EOL;
                $code.= 'RewriteBase /'.$site['mobile']['dirname'].'/'.PHP_EOL
                    .'RewriteCond %{REQUEST_FILENAME} !-f'.PHP_EOL
                    .'RewriteCond %{REQUEST_FILENAME} !-d'.PHP_EOL
                    .'RewriteRule !.(js|ico|gif|jpe?g|bmp|png|css)$ /'.$site['mobile']['dirname'].'/index.php [NC,L]'.PHP_EOL.PHP_EOL;
                $code.= '####以上目录需要单独保持到/'.$site['mobile']['dirname'].'/.htaccess文件中';
            }
            // 主目录
            $code.= 'RewriteEngine On'.PHP_EOL.PHP_EOL;
            $code.= 'RewriteBase '.$root.'/'.PHP_EOL
                .'RewriteCond %{REQUEST_FILENAME} !-f'.PHP_EOL
                .'RewriteCond %{REQUEST_FILENAME} !-d'.PHP_EOL
                .'RewriteRule !.(js|ico|gif|jpe?g|bmp|png|css)$ '.$root.'/index.php [NC,L]'.PHP_EOL.PHP_EOL;
        } elseif (strpos($server, 'nginx') !== FALSE) {
            $name = $server;
            $note = '<font color=red><b>将以下代码放到Nginx配置文件中去（如果是绑定了域名，所绑定目录也要配置下面的代码）</b></font>';
            // 子目录
            $code = '###当存在多个子目录格式的域名时，需要多写几组location标签：location /目录/ '.PHP_EOL;
            if (isset($site['mobile']['mode']) && $site['mobile']['mode'] && $site['mobile']['dirname']) {
                $code.= 'location '.$root.'/'.$site['mobile']['dirname'].'/ { '.PHP_EOL
                    .'    if (-f $request_filename) {'.PHP_EOL
                    .'           break;'.PHP_EOL
                    .'    }'.PHP_EOL
                    .'    if ($request_filename ~* "\.(js|ico|gif|jpe?g|bmp|png|css)$") {'.PHP_EOL
                    .'        break;'.PHP_EOL
                    .'    }'.PHP_EOL
                    .'    if (!-e $request_filename) {'.PHP_EOL
                    .'        rewrite . '.$root.'/'.$site['mobile']['dirname'].'/index.php last;'.PHP_EOL
                    .'    }'.PHP_EOL
                    .'}'.PHP_EOL.PHP_EOL;
            }
            // 主目录
            $code.= 'location '.$root.'/ { '.PHP_EOL
                .'    if (-f $request_filename) {'.PHP_EOL
                .'           break;'.PHP_EOL
                .'    }'.PHP_EOL
                .'    if ($request_filename ~* "\.(js|ico|gif|jpe?g|bmp|png|css)$") {'.PHP_EOL
                .'        break;'.PHP_EOL
                .'    }'.PHP_EOL
                .'    if (!-e $request_filename) {'.PHP_EOL
                .'        rewrite . '.$root.'/index.php last;'.PHP_EOL
                .'    }'.PHP_EOL
                .'}'.PHP_EOL;
        } else {
            $name = $server;
            $note = '<font color=red><b>无法为此服务器提供伪静态规则，建议让运营商帮你把下面的Apache规则做转换</b></font>';
            $code = 'RewriteEngine On'.PHP_EOL
                .'RewriteBase /'.PHP_EOL
                .'RewriteCond %{REQUEST_FILENAME} !-f'.PHP_EOL
                .'RewriteCond %{REQUEST_FILENAME} !-d'.PHP_EOL
                .'RewriteRule !.(js|ico|gif|jpe?g|bmp|png|css)$ /index.php [NC,L]';
        }

        \Phpcmf\Service::V()->assign([
            'name' => $name,
            'code' => $code,
            'note' => $note,
            'domain' => $domain,
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '伪静态代码' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-link'],
                ]
            ),
            'count' => $code ? dr_count(explode(PHP_EOL, $code)) : 0,
        ]);
        \Phpcmf\Service::V()->display('urlrule_code.html');exit;
    }

}

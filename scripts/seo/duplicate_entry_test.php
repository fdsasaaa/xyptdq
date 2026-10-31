<?php
/** Exercise the actual PC/mobile headers over HTTP, including status and Location. */
declare(strict_types=1);
$root=dirname(__DIR__,2);
$tmp=sys_get_temp_dir().'/xyptdq-duplicate-entry-'.getmypid();
mkdir($tmp,0700,true);
$router=$tmp.'/router.php';
$source='<?php define("MOD_DIR", $_GET["module"]??"news"); $meta_title="Fixture title"; $meta_description="Fixture description"; $meta_keywords=""; require '.var_export($root,true).'."/site/template/".($_GET["view"]??"pc")."/default/home/seo_header.html";';
file_put_contents($router,$source);
$socket=stream_socket_server('tcp://127.0.0.1:0',$errno,$errstr);
if (!$socket) {throw new RuntimeException('test listener unavailable');}
$address=stream_socket_get_name($socket,false); fclose($socket);
$process=proc_open(escapeshellarg(PHP_BINARY).' -S '.escapeshellarg($address).' '.escapeshellarg($router),
    [0=>['file','/dev/null','r'],1=>['file',$tmp.'/server.log','a'],2=>['file',$tmp.'/server.log','a']],$pipes);
if (!is_resource($process)) {throw new RuntimeException('test server unavailable');}
try {
    $ready=false;
    for ($i=0;$i<60;$i++) {
        $s=@stream_socket_client('tcp://'.$address,$errno,$errstr,0.1);
        if ($s) {fclose($s);$ready=true;break;} usleep(50000);
    }
    if (!$ready) {throw new RuntimeException('test server startup failed');}
    foreach (['pc','mobile'] as $view) {
        foreach ([[106,'news',301],[105,'news',200],[104,'news',200],[106,'xm',200]] as $case) {
            [$id,$module,$expected]=$case;
            $ctx=stream_context_create(['http'=>['follow_location'=>0,'ignore_errors'=>true,'timeout'=>5]]);
            $body=file_get_contents('http://'.$address.'/?c=show&id='.$id.'&view='.$view.'&module='.$module,false,$ctx);
            $headers=$http_response_header??[];
            if (!isset($headers[0]) || strpos($headers[0],' '.$expected.' ')===false) {
                throw new RuntimeException($view.' unexpected HTTP status: '.json_encode($headers));
            }
            if ($expected===301) {
                if (!in_array('Location: https://www.laocaimi.org/index.php?c=show&id=105',$headers,true)) {
                    throw new RuntimeException('duplicate entry Location mismatch');
                }
            } elseif (strpos((string)$body,'rel="canonical" href="https://www.laocaimi.org/index.php?c=show&amp;id='.$id.'"')===false) {
                throw new RuntimeException('unrelated canonical changed: '.$view.'/'.$module.'/'.$id);
            }
        }
    }
    echo "[duplicate-entry-test] PASS pc/mobile=301 originals=200 unrelated-module=unchanged\n";
} finally {
    proc_terminate($process); proc_close($process);
    foreach (glob($tmp.'/*')?:[] as $p) {unlink($p);} rmdir($tmp);
}

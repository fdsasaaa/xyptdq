<?php namespace Phpcmf\Controllers\Admin;

class Home extends \Phpcmf\App
{

    public function index() {
        \Phpcmf\Service::V()->assign([
            'menu' => \Phpcmf\Service::M('auth')->_admin_menu(
                [
                    '字段标签调用' => [APP_DIR.'/'.\Phpcmf\Service::L('Router')->class.'/index', 'fa fa-tag'],
                ]
            ),
            'list' => [
                [
                    'name' => '网站信息调用',
                    'uri' => 'mbdy/site/index',
                    'msg' => '设置-网站信息-自定义字段',
                ],
                [
                    'name' => '模块字段调用',
                    'uri' => 'mbdy/module/index',
                    'msg' => '设置-内容设置-模块管理，模块内容字段',
                ],
                [
                    'name' => '栏目循环调用',
                    'uri' => 'mbdy/categoryshow/index',
                    'msg' => '内容-栏目管理，自定义字段',
                ],
                [
                    'name' => '栏目字段调用',
                    'uri' => 'mbdy/category/index',
                    'msg' => '内容-栏目管理，自定义字段',
                ],
                [
                    'name' => '栏目模型字段调用',
                    'uri' => 'mbdy/categorydata/index',
                    'msg' => '设置-内容设置-模块管理，栏目模型字段',
                ],
                [
                    'name' => '评论字段调用',
                    'uri' => 'mbdy/comment/index',
                    'msg' => '插件-评论系统-选择对应的菜单，安装好评论，评论字段里面',
                ],
                [
                    'name' => '表单字段调用',
                    'uri' => 'mbdy/form/index',
                    'msg' => '设置-网站表单管理，自定义字段',
                ],
                [
                    'name' => '模块表单字段调用',
                    'uri' => 'mbdy/mform/index',
                    'msg' => '设置-内容设置-模块内容表单-选择某个模块-模块表单，自定义字段',
                ],
                [
                    'name' => '会员信息调用',
                    'uri' => 'mbdy/member/index',
                    'msg' => '设置-用户设置-字段划分，自定义字段',
                ],
                [
                    'name' => '联动菜单字段调用',
                    'uri' => 'mbdy/linkage/index',
                    'msg' => '插件-联动菜单-选择某个菜单，自定义字段',
                ],
            ],
        ]);
        \Phpcmf\Service::V()->display('index.html');
    }


    public function show() {

    }

    public function qqun() {

        $img = dr_get_app_dir(APP_DIR).'Config/qq.jpg';
        $info = getimagesize($img);
        $imgExt = image_type_to_extension($info[2], false);  //获取文件后缀
        $fun = "imagecreatefrom{$imgExt}";
        $imgInfo = $fun($img); 					//1.由文件或 URL 创建一个新图象。如:imagecreatefrompng ( string $filename )
        //$mime = $info['mime'];
        $mime = image_type_to_mime_type($info[2]); //获取图片的 MIME 类型
        header('Content-Type:'.$mime);
        $quality = 100;
        if($imgExt == 'png') $quality = 9;		//输出质量,JPEG格式(0-100),PNG格式(0-9)
        $getImgInfo = "image{$imgExt}";
        $getImgInfo($imgInfo, null, $quality);	//2.将图像输出到浏览器或文件。如: imagepng ( resource $image )
        imagedestroy($imgInfo);

    }

}

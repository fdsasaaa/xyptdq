<?php

// 自动加载识别文件

return [

    /**
     * 命名空间映射关系
     */
    'psr4' => [


    ],

    /**
     * 类名映射关系
     */
    'classmap' => [

        'Phpcmf\Admin\File'        => dr_get_app_dir('tpl').'Controllers/File.php',
        'Phpcmf\Admin\Devfile'     => dr_get_app_dir('tpl').'Controllers/Devfile.php',

    ],


];
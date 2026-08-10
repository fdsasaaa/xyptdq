<?php

/**
 * 菜单配置
 */


return [

    'admin' => [


        'code' => [
            'name' => '界面',
            'icon' => 'fa fa-html5',
            'left' => [
                'dev-html' => [
                    'name' => '界面编辑',
                    'icon' => 'fa fa-home',
                    'link' => [
                        [
                            'name' => '电脑界面',
                            'icon' => 'fa fa-desktop',
                            'uri' => 'tpl/dev_pc/index',
                        ],
                        [
                            'name' => '手机界面',
                            'icon' => 'fa fa-mobile',
                            'uri' => 'tpl/dev_mobile/index',
                        ],
                    ]
                ],
                'code-html' => [
                    'name' => '模板代码',
                    'icon' => 'fa fa-code',
                    'link' => [
                        [
                            'name' => '电脑模板',
                            'icon' => 'fa fa-desktop',
                            'uri' => 'tpl/tpl_pc/index',
                        ],
                        [
                            'name' => '手机模板',
                            'icon' => 'fa fa-mobile',
                            'uri' => 'tpl/tpl_mobile/index',
                        ],
                        [
                            'name' => '终端模板',
                            'icon' => 'fa fa-cogs',
                            'uri' => 'tpl/tpl_client/index',
                        ],
                    ]
                ],
                'code-css' => [
                    'name' => '风格代码',
                    'icon' => 'fa fa-css3',
                    'link' => [
                        [
                            'name' => '系统文件',
                            'icon' => 'fa fa-chrome',
                            'uri' => 'tpl/system_theme/index',
                        ],
                        [
                            'name' => '项目风格',
                            'icon' => 'fa fa-photo',
                            'uri' => 'tpl/theme/index',
                        ],
                        [
                            'name' => '手机风格',
                            'icon' => 'fa fa-mobile',
                            'uri' => 'tpl/theme_mobile/index',
                        ],
                    ],
                    'displayorder' => 99
                ],
            ],
        ],


    ],



];
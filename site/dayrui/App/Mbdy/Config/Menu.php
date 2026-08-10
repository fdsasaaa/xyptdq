<?php

/**
 * 菜单配置
 */


return [

    'admin' => [

        'app' => [

            'left' => [


                'app-mbdy' => [
                    'name' => '模板调用工具',
                    'icon' => 'fa fa-tag',
                    'link' => [
                         [
                            'name' => '字段调用标签',
                            'icon' => 'fa fa-list',
                            'uri' => 'mbdy/home/index',
                         ],

                         [
                            'name' => '页面标签调用',
                            'icon' => 'fa fa-list',
                            'uri' => 'mbdy/page/index',
                         ],

                        [
                            'name' => '循环标签调用',
                            'icon' => 'fa fa-list',
                            'uri' => 'mbdy/loop/index',
                        ],

                        [
                            'name' => '内容搜索条件',
                            'icon' => 'fa fa-search',
                            'uri' => 'mbdy/search/index',
                        ],

                    ]
                ],
            ],



        ],

    ],
];
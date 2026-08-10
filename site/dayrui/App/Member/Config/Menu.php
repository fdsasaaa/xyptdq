<?php

/**
 * 菜单配置
 */


return [

    'admin' => [
        'auth' => [
            'left' => [
                'app-member' => [
                    'name' => '用户权限',
                    'icon' => 'fa fa-user',
                    'link' => [
                        [
                            'name' => '审核流程',
                            'icon' => 'fa fa-sort-numeric-asc',
                            'uri' => 'member/admin_verify/index',
                        ],
                        [
                            'name' => '用户菜单',
                            'icon' => 'fa fa-list-alt',
                            'uri' => 'member/menu/index',
                        ],
                        [
                            'name' => '用户权限',
                            'icon' => 'fa fa-user',
                            'uri' => 'member/auth/index',
                        ],
                    ]
                ],
            ],
        ],

        'member' => [
            'name' => '用户',
            'icon' => 'fa fa-user',
            'left' => [
                'member-list' => [
                    'name' => '用户管理',
                    'icon' => 'fa fa-user',
                    'link' => [
                        [
                            'name' => '用户管理',
                            'icon' => 'fa fa-user',
                            'uri' => 'member/home/index',
                            'displayorder' => '-1',
                        ],
                        [
                            'name' => '用户组管理',
                            'icon' => 'fa fa-users',
                            'uri' => 'member/group/index',
                            'displayorder' => '-1',
                        ],
                        [
                            'name' => '授权账号管理',
                            'icon' => 'fa fa-qq',
                            'uri' => 'member/oauth/index',
                        ],
                    ]
                ],
                'config-member' => [
                    'name' => '用户设置',
                    'icon' => 'fa fa-user',
                    'link' => [
                        [
                            'name' => '用户设置',
                            'icon' => 'fa fa-cog',
                            'uri' => 'member/setting/index',
                        ],
                        [
                            'name' => '字段划分',
                            'icon' => 'fa fa-code',
                            'uri' => 'member/field/index',
                        ],
                        [
                            'name' => '通知设置',
                            'icon' => 'fa fa-volume-up',
                            'uri' => 'member/setting_notice/index',
                        ],
                    ]
                ],
                'member-verify' => [
                    'name' => '审核管理',
                    'icon' => 'fa fa-edit',
                    'link' => [
                        [
                            'name' => '注册审核',
                            'icon' => 'fa fa-user',
                            'uri' => 'member/verify/index',
                        ],
                        [
                            'name' => '申请审核',
                            'icon' => 'fa fa-users',
                            'uri' => 'member/apply/index',
                        ],
                        [
                            'name' => '资料审核',
                            'icon' => 'fa fa-edit',
                            'uri' => 'member/edit_verify/index',
                        ],
                        [
                            'name' => '头像审核',
                            'icon' => 'fa fa-user-circle',
                            'uri' => 'member/avatar_verify/index',
                        ],
                    ]
                ],

            ],
        ],

    ],


    'member' => [

        'user' => [
            'name' => '账号管理',
            'icon' => 'fa fa-user',
            'link' => [
                [
                    'name' => '资料修改',
                    'icon' => 'fa fa-cog',
                    'uri' => 'account/index',
                ],
                [
                    'name' => '头像设置',
                    'icon' => 'fa fa-smile-o',
                    'uri' => 'account/avatar',
                ],
                [
                    'name' => '手机认证',
                    'icon' => 'fa fa-mobile',
                    'uri' => 'account/mobile',
                ],
                [
                    'name' => '邮箱认证',
                    'icon' => 'fa fa-envelope',
                    'uri' => 'account/email',
                ],
                [
                    'name' => '修改密码',
                    'icon' => 'fa fa-expeditedssl',
                    'uri' => 'account/password',
                ],
                [
                    'name' => '账号绑定',
                    'icon' => 'fa fa-qq',
                    'uri' => 'account/oauth',
                ],
                [
                    'name' => '登录记录',
                    'icon' => 'fa fa-calendar',
                    'uri' => 'account/login',
                ],
            ],
        ],

        'content-module' => [
            'name' => '内容管理',
            'icon' => 'fa fa-th-large',
            'link' => [

            ],
        ],


    ],
];
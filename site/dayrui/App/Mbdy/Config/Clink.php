<?php

return [

    [
        'name' => '前端调用', // 站点权限是插件的链接名称
        'icon' => 'fa fa-code', // 图标
        'color' => 'yellow', // 颜色class red green blue
        'url' => 'javascript:dr_iframe_show(\'\', \''.SELF.'?s=mbdy&c=module&m=show&mid={mid}&id={cid}\')', // 后台链接：对于点击的地址mid是模块目录，cid是内容id
        'uri' => 'mbdy/module/index', // 对应的uri权限判断，后面章节会介绍权限写法
        'field' => '', // 统计数量的字段，填写模块内容的主表字段，只能填写int数字类型的字段
    ],

];
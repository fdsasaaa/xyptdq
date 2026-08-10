<?php

/**
 * URL解析规则
 * 例如：  114.html 对应 index.php?s=demo&c=show&id=114
 * 可以解析：  "114.html"  => 'index.php?s=demo&c=show&id=114',
 * 动态id解析：  "([0-9]+).html"  => 'index.php?s=demo&c=show&id=$1',
 */

return [

    "list-([A-za-z0-9 \-\_]+)-([0-9]+)\.html" => "index.php?c=category&dir=$1&page=$2",  //【不带栏目路径】模块栏目列表(分页)（list-{dirname}-{page}.html）
    "list-([A-za-z0-9 \-\_]+)\.html" => "index.php?c=category&dir=$1",  //【不带栏目路径】模块栏目列表（list-{dirname}.html）
    "show-([0-9]+)\.html" => "index.php?c=show&id=$1",  //【不带栏目路径】模块内容页（show-{id}.html）

    "search\/([a-z]+)\/(.+)\.html" => "index.php?s=$1&c=search&rewrite=$2",  //【共享模块搜索】模块搜索页(分页)（search/{modname}/{param}.html）
    "search\/([a-z]+)\.html" => "index.php?s=$1&c=search",  //【共享模块搜索】模块搜索页（search/{modname}.html）


    "([A-za-z0-9 \-\_]+)\/p([0-9]+)\.html" => "index.php?c=category&dir=$1&page=$2",  //【带栏目路径】模块栏目列表(分页)（{dirname}/p{page}.html）
    "([A-za-z0-9 \-\_]+)\/([0-9]+)\.html" => "index.php?c=show&id=$2",  //【带栏目路径】模块内容页（{dirname}/{id}.html）
    "([A-za-z0-9 \-\_]+)" => "index.php?c=category&dir=$1",  //【带栏目路径】模块栏目列表（{dirname}）

];
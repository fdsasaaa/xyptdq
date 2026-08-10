&lt;?php if ($value) { foreach ($value2 as $v) { ?>
----------
    栏目名称：{dr_cat_value('模块目录', $v, 'name')}
    栏目地址：{dr_cat_value('模块目录', $v, 'url')}
---------
&lt;?php } } ?>
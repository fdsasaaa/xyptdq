&lt;?php if ($value) { foreach ($value2 as $v) { ?>
属性名：{$v.name}
属性值：{$v.value}
&lt;?php } } ?>

---------单独输出某一行-----------
{php $myvalue=$value2;} 这句话必须要,配合下面的标签进行输出
第一行名称：{$myvalue[0]['name']}  // 0是行号，可以随时变动
第一行值：{$myvalue[0]['value']}
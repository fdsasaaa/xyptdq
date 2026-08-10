&lt;?php if ($value) { foreach ($value2 as $v) { ?>
-------
联动菜单名称：{dr_linkage('$linkname', $v, 0, 'name')}
联动菜单顶级的名称：{dr_linkage('$linkname', $v, 1, 'name')}
面包屑导航：{dr_linkagepos('$linkname', $v, ' - ')}
-------
&lt;?php } } ?>
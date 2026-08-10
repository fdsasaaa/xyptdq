<?php

$html=dr_html2code('
一级栏目分类
<a class=" {if !$cat}高亮选中{/if}" href="{Router::search_url($params, \'catid\', NULL, \''.$mid.'\')}">不限</a>
{category pid=0}
<a class=" {if dr_in_array($cat.id, $t.catids)}高亮选中{/if}" href="{Router::search_url($params, \'catid\', $t.id, \''.$mid.'\')}">{$t.name}</a>
{/category}

------------------
二级栏目分类或下级分类
{if $cat}
<a class=" {if $cat.child}高亮选中{/if}" href="{Router::search_url($params, \'catid\', $cat.id, \''.$mid.'\')}">不限</a>
{loop $related $t}
<a class=" {if $t.id==$cat.id}高亮选中{/if}" href="{Router::search_url($params, \'catid\', $t.id, \''.$mid.'\')}">{$t.name}</a></label>
{/loop}
{/if}
');
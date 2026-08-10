{php $tags = dr_get_content_tags($value);}
<br>
{loop $tags $name0 $url0}
{$url0}
{$name0}
{/loop}
<hr>
只想输出3个词语写法<br>
{php $tags = dr_arraycut(dr_get_content_tags($value), 3);}
<br>
{loop $tags $name0 $url0}
{$url0}
{$name0}
{/loop}
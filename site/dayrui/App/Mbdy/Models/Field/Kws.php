{php $kws = dr_get_content_kws($value, 'MOD_DIR');}
<br>
{loop $kws $name00 $url00}
{$url00}
{$name00}
{/loop}
<hr>
只想输出3个词语写法<br>
{php $kws = dr_arraycut(dr_get_content_kws($value, 'MOD_DIR'), 3);}
<br>
{loop $kws $name00 $url00}
{$url00}
{$name00}
{/loop}
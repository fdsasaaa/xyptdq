<?php

$html = '
<a class="{if !$params.'.$fid.'}选中高亮{/if}" href="{dr_search_url($params, \''.$fid.'\', NULL, \''.$mid.'\')}">不限</a>
{php $field = dr_field_options('.$field['id'].');}
{loop $field $value $name}
<a class="{if $value==$params.'.$fid.'}选中高亮{/if}" href="{dr_search_url($params, \''.$fid.'\', $value, \''.$mid.'\')}">{$name}</a></label>
{/loop}


====================多选模式====================
{php $field = dr_field_options('.$field['id'].');}
{loop $field $value $name}
<a class="{if dr_is_double_search($params.'.$fid.', $value)}选中高亮{/if}" href="{Router::search_url($params, \''.$fid.'\', dr_get_double_search($params.'.$fid.', $value, \''.$mid.'\'))}">{$name}</a>
{/loop}
';

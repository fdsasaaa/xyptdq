<?php

$html = '
<a class="{if !$params.'.$fid.' || dr_linkage(\''.$field['setting']['option']['linkage'].'\', $params.'.$fid.', 0, \'child\')}高亮选中{/if}" href="{dr_search_url($params, \''.$fid.'\', NULL, \''.$mid.'\')}">不限</a>
{linkage code='.$field['setting']['option']['linkage'].' pid=$params.'.$fid.'}
<a class="{if $t.id==$params.'.$fid.'}高亮选中{/if}" href="{dr_search_url($params, \''.$fid.'\', $t.id, \''.$mid.'\')}">{$t.name}</a>
{/linkage}

';

<?php $my = \Phpcmf\Service::C()->get_cache('table-field', $fid, 'setting', 'option', 'value');?>
<?php $my && preg_match_all('/\{(.+)\}/U', $my, $value);?>
{if $value[1]}
{loop $value[1] $v}
已选字段：{$v}
{/loop}
{/if}
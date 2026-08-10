{if $value_sku}
按用户组的值：
{php $vsku = dr_string2array($value_sku);}
{cache name=member_group return=mc}
用户组【{$mc.name}】: {$vsku[$mc.id]}
{/cache}
{else}
全局值：{$value}
{/if}
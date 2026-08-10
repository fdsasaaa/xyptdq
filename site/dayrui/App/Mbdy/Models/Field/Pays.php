普通输出：{$value}
最小价格值：{dr_price_value($value)}
价格的范围值：{dr_sku_price($sku, 2, ' ~ ')}

数量输出：{$quantity}
编码输出：{$sn}

属性规格输出：
{if $sku}
{loop $sku['group'] $gid $gname}
{if $gname}
---分组名称：{$gname}
{loop $sku['name'][$gid] $vid $vname}
------属性名称：{$vname}
------编码sn:{$sku['value'][$gid.'_'.$vid]['sn']}
------价格:{$sku['value'][$gid.'_'.$vid]['price']}
------数量:{$sku['value'][$gid.'_'.$vid]['quantity']}
------图片:{dr_thumb($sku['value'][$gid.'_'.$vid]['image'])}
------其他字段:{$sku['value'][$gid.'_'.$vid]['其他字段名称']}
---------------------
{/loop}
------------------------------
{/if}
{/loop}
{else}
没设置规格属性
{/if}
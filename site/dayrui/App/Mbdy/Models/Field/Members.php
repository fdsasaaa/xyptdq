{if $value}
{member IN_id=$value return=r}
{$r.id}
{$r.username}
{dr_avatar($r.id)}
......
{/member}
{else}
没有关联
{/if}
------------------
数据个数：{php echo $value ? substr_count(trim($value, ','), ',')+1 : 0;}
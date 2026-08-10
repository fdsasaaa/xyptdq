加入了哪些用户组：
<pre>
{loop $value $tt}
    用户组ID：{$tt.gid} 这是gid不要写成id
    级别名称：{$tt.group_level}
    用户组名称：{$tt.group_name}
    有效期：{dr_date($tt.stime)} ~ {dr_date($tt.etime)}
{/loop}
</pre>
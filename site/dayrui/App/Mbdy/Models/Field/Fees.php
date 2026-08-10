针对会员组等级的设置的价格调用：

<table>
    {list action=cache name=MEMBER.group return=group}
    {if $group.id > 2}
    <tr>
        <td align="left" width="90">{$group.name}</td>
        <td align="left"></td>
    </tr>
    {loop $group.level $level}
    <tr>
        {php $lid=$group['id'].'_'.$level['id'];}
        <td align="left" style="padding-left:40px">{$level.name}</td>
        <td align="left">
            {$value[$lid]} {SITE_SCORE}
        </td>
    </tr>
    {/loop}
    {/if}
    {/list}
</table>

针对会员组设置的价格调用

<table>
    {list action=cache name=MEMBER.group return=group}
    {if $group.id > 2}
    <tr>
        <td align="left" width="90">{$group.name}</td>
        <td align="left">
            {$value[$group.id]}{SITE_SCORE}
        </td>
    </tr>
    {/if}
    {/list}
</table>

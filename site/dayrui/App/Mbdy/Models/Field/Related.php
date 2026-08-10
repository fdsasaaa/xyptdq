{if $value}
{module module=$module IN_id=$value return=r}
序号：{$key_r+1}
地址：{$r.url}
标题：{$r.title}
其他字段可以在这里生成：
类别选择：（在自定义字段管理里面看），名称填写：（也在自定义字段管理里面），前缀：填写r，生成地址：https://www.xunruicms.com/doc/code/field.html
......
{/module}
{else}
没有关联
{/if}
------------------
数据个数：{php echo $value ? substr_count(trim($value, ','), ',')+1 : 0;}
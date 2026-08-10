选择值：{$value}
<p>判断值：{if $value == "填写值"} 表示条件成功 {/if} </p>
选择的名称：{php $field = dr_field_options($fid);}{$field[$value]}
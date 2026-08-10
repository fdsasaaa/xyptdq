<?php
/**
 * 示例文件
 * 变量介绍
 * $name 字段英文名称
 * $field 字段信息（数组）
 * $value 当前字段的值
 * \Phpcmf\Service::C() 表示控制器方法
 * \Phpcmf\Service::M() 表示模型方法
 * 表单的name值格式是：data[$name]
 */

$avatar_url = dr_member_verify_avatar_url($value);

$code = '<label><span href="javascript:;" class="thumbnail"><img src="'.$avatar_url.'" style="height: 180px; width: 100%; display: block;"> </span></label>'; // 最终输出的代码
普通输出：{$value}
按HTML模式显示：{dr_code2html($value)}
截取10个字输出（超出的加...）：{dr_strcut($value, 10, '...')}
截取10个字输出（超出的不加）：{dr_strcut($value, 10, '')}
先清理html标记后截取10个字输出（超出的不加）：{dr_strcut(dr_clearhtml($value), 10, '')}

从第5个字符开始截取10个字输出：{mb_substr($value, 5, 10)}
<hr>
保留小数位1位：{number_format($value, 1)}
保留小数位2位：{number_format($value, 2)}

转为数字输出：{intval($value)}
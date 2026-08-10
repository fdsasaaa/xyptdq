原始文件的地址：{dr_get_file($value)}
文件的下载地址：{dr_down_file($value)}
文件的下载地址并指定文件名字：{dr_down_file($value, '新名字')}
缩略图地址：{dr_thumb($value, 100, 100)}
缩略图带上水印地址：{dr_thumb($value, 100, 100, 1)}
缩略图带上水印地址：{dr_thumb($value, 100, 100, 1)}
缩略图从中间开始剪切，高度宽度固定：{dr_thumb($value, 100, 100, 0, 'crop')}
对url地址进行缩略处理：{dr_thumb($value, 100, 100, 0, '', 1)}
--------判断是否为空--------
{if $value}有 {else} 无{/if}
{if $value}有 {/if}

===========================
--------附件详情信息---------
{php $myfile=\Phpcmf\Service::C()->get_attachment($value);}
附件名称:{$myfile.filename}
附件扩展名:{$myfile.fileext}
上传时间:{dr_date($myfile.inputtime)}
附件大小:{dr_format_file_size($myfile.filesize)}
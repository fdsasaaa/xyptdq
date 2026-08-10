总数量：{dr_count($value2)}
==============循环遍历显示 - 开始=============
可选：&lt;?php $value = dr_arraycut($value2, 3);?> // 3表示显示几个。 加上这句话在前面，表示从开头开始只显示循环3个文件，不加表示循环全部
开始：
&lt;?php if ($value) { $key=0;foreach ($value2 as $c) { ?>
    序号: {$key+1}
    标题：{$c.title}
    描述：{$c.description}
    文件原始地址：{dr_get_file($c.file)}
    文件的下载地址：{dr_down_file($c.file)}
    文件的下载地址并指定文件名字：{dr_down_file($c.file, '新名字')}
    图片缩略图：{dr_thumb($c.file, 200, 200)}
    图片缩略图带水印：{dr_thumb($c.file, 200, 200, 1)}
    缩略图从中间开始剪切，高度宽度固定：{dr_thumb($c.file, 100, 100, 0, 'crop')}
    对url地址进行缩略处理：{dr_thumb($c.file, 100, 100, 0, '', 1)}
    ----------------------------------
    {php $myfile=\Phpcmf\Service::C()->get_attachment($c.file);}
    调用文件作者:{$myfile.author}
    附件名称:{$myfile.filename}
    附件大小:{dr_format_file_size($myfile.filesize)}
    附件扩展名:{$myfile.fileext}
    ----------------------------------
&lt;?php $key++;} } ?>
==============循环遍历显示 - 完毕=============

==============只显示第一个文件=============
{php $c = current($value2);}
文件原始地址：{dr_get_file($c.file)}
文件的下载地址：{dr_down_file($c.file)}
文件的下载地址并指定文件名字：{dr_down_file($c.file, '新名字')}
图片缩略图：{dr_thumb($c.file, 200, 200)}
普通输出：{$value}
相对路径输出（需后台开启相对路径模式）：{dr_text_rel($value)}
去掉html标签：{dr_clearhtml($value)}
去掉html标签再截10个字：{dr_strcut(dr_clearhtml($value), 10, '...')}
去掉html标签只保留中文：{dr_html2text($value, 1)}
去掉html标签只保留中文再截10个字：{dr_strcut(dr_html2text($value, 1), 10, '...')}
<hr>
(针对上面无效时的用法)普通输出：{dr_code2html($value)}
(针对上面无效时的用法)去掉html标签：{dr_clearhtml(dr_code2html($value))}
(针对上面无效时的用法)去掉html标签再截10个字：{dr_strcut(dr_clearhtml(dr_code2html($value)), 10, '...')}
<hr>
读取内容字段中的全部图片
{php $imgs = dr_get_content_img($value);}
{loop $imgs $img}
{$img}
{/loop}
图片数量：{count($imgs)}
<hr>
提取3张图片写法：
{php $imgs = dr_get_content_img($value, 3);}
{loop $imgs $img}
{$img}
{/loop}
<hr>
提取一张图片的写法：
{php $imgs = dr_get_content_img($content, 1);}
{$imgs[0]}
<hr>
读取内容字段中的全部视频地址
{php $videos = dr_get_content_url($value, 'src', 'mp4'));}
{loop $videos $video}
{$video}
{/loop}
视频数量：{count($videos)}
<hr>
提取一张视频的写法：
{php $videos = dr_get_content_url($content, 'src', 'mp4', 1);}
{$videos[0]}
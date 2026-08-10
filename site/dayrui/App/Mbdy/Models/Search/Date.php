<?php

$html=dr_html2code('
{php $time = explode(\',\', $params.'.$fid.');}
<input type="text" value="{$time[0]}" id="where_'.$fid.'_min">-<input type="text" value="{$time[1]}" id="where_'.$fid.'_max">
<button onclick="xb_'.$fid.'_search()" type="button"> 时间范围搜索</button>
<script>
    function xb_'.$fid.'_search(name) {
        var url="{dr_search_url($params, \''.$fid.'\', \'xbmbdy\', \''.$mid.'\')}";
        var min = $("#where_'.$fid.'_min").val();
        var max = $("#where_'.$fid.'_max").val();
        max = max ? max : 0;
        min = min ? min : 0;
        if (max || min) {
            url = url.replace(\'xbmbdy\', min+\',\'+max);
        } else {
            url = url.replace(\'xbmbdy\', \'\');
        }
        location.href=url;
        return false;
    }
</script>
');
<?php

$html=dr_html2code('
<input type="text" name="keyword" value="{$keyword}" id="search_keyword">
<button onclick="dr_module_search()" type="button"> 模糊搜索</button>
<script>
    function dr_module_search(name) {
        var url="{dr_search_url($params, \'keyword\', \'xbmbdy\', \''.$mid.'\')}";
        var val = $("#search_keyword").val();
        if (val) {
            url = url.replace(\'xbmbdy\', val);
        } else {
            url = url.replace(\'xbmbdy\', \'\');
        }
        location.href=url;
        return false;
    }
</script>
');
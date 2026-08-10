<?php
// 会员信息

$tableinfo = \Phpcmf\Service::L('cache')->get('table-'.$system['site']);
if (!$tableinfo) {
    // 没有表结构缓存时返回空
    return $this->_return($system['return'], '表结构缓存不存在');
}

$table = \Phpcmf\Service::M()->dbprefix('member'); // 主表
if (!isset($tableinfo[$table])) {
    return $this->_return($system['return'], '表（'.$table.'）结构缓存不存在');
}

$fields = \Phpcmf\Service::C()->get_cache('member', 'field');

// 是否操作自定义where
if ($param['where']) {
    $where[] = [
        'adj' => 'SQL',
        'value' => urldecode($param['where'])
    ];
    unset($param['where']);
}

// groupid查询
if (isset($param['groupid']) && $param['groupid']) {

    if (strpos($param['groupid'], ',') !== false) {
        $gwhere = ' `'.$table.'`.`id` in (select uid from `'.$table.'_group_index` where `gid` in ('.dr_safe_replace($param['groupid']).'))';
    } elseif (strpos($param['groupid'], '-') !== false) {
        $arr = explode('-', $param['groupid']);
        $gwhere = [];
        foreach ($arr as $t) {
            $t = intval($t);
            $t && $gwhere[] = ' `'.$table.'`.`id` in (select uid from `'.$table.'_group_index` where `gid` = '. $t.')';
        }
        $gwhere = $gwhere ? '('.implode(' AND ', $gwhere).')' : '';
    } else {
        $gwhere = ' `'.$table.'`.`id` in (select uid from `'.$table.'_group_index` where `gid` = '. intval($param['groupid']).')';
    }

    $gwhere && $where['id'] = [
        'adj' => 'SQL',
        'name' => 'id',
        'value' => $gwhere
    ];
    unset($param['groupid']);
}

$system['order'] = !$system['order'] ? 'id' : $system['order']; // 默认排序参数

$where = $this->_set_where_field_prefix($where, $tableinfo[$table], $table, $fields); // 给条件字段加上表前缀
$system['field'] = $this->_set_select_field_prefix($system['field'], $tableinfo[$table], $table); // 给显示字段加上表前缀

// 多表组合排序
$_order = [];
$_order[$table] = $tableinfo[$table];

$sql_from = $table; // sql的from子句

if ($system['more']) {
    // 会员附表
    $more = \Phpcmf\Service::M()->dbprefix('member_data'); // 附表
    $where = $this->_set_where_field_prefix($where, $tableinfo[$more], $more, $fields); // 给条件字段加上表前缀
    $system['field'] = $this->_set_select_field_prefix($system['field'], $tableinfo[$more], $more); // 给显示字段加上表前缀
    $_order[$more] = $tableinfo[$more];
    $sql_from.= " LEFT JOIN $more ON `$table`.`id`=`$more`.`id`"; // sql的from子句
}

// 关联表
if ($system['join'] && $system['on']) {
    $rt = $this->_join_table($table, $system, $where, $_order, $sql_from);
    if (!$rt['code']) {
        return $this->_return($system['return'], $rt['msg']);
    }
    list($system, $where, $_order, $sql_from) = $rt['data'];
}

$total = 0;
$sql_limit = '';
$sql_where = $this->_get_where($where); // sql的where子句

// 统计标签
if ($this->_return_sql) {
    $sql = "SELECT ".$this->_select_rt_name." FROM $sql_from ".($sql_where ? "WHERE $sql_where" : "")." ORDER BY NULL";
} else {
    if ($system['page']) { // 如存在分页条件才进行分页查询
        $page = $this->_get_page_id($system['page']);
        $pagesize = (int)$system['pagesize'];
        $pagesize = $pagesize ? $pagesize : 10;
        $sql = "SELECT count(*) as c FROM $sql_from " . ($sql_where ? "WHERE $sql_where" : "") . " ORDER BY NULL";
        $row = $this->_query($sql, $system, FALSE);
        $total = (int)$row['c'];
        if (!$total) {
            // 没有数据时返回空
            return $this->_return($system['return'], '没有查询到内容', $sql, 0);
        }
        $sql_limit = ' LIMIT ' . intval($pagesize * ($page - 1)) . ',' . $pagesize;
        $pages = $this->_new_pagination($system, $pagesize, $total);
    } elseif ($system['num']) {
        $sql_limit = "LIMIT {$system['num']}";
    }

    $system['order'] = $this->_set_orders_field_prefix($system['order'], $_order); // 给排序字段加上表前缀
    $sql = "SELECT " . $this->_get_select_field($system['field'] ? $system['field'] : "*") . " FROM $sql_from " . ($sql_where ? "WHERE $sql_where" : "") . " " . ($system['order'] == "null" || !$system['order'] ? "" : " ORDER BY {$system['order']}") . " $sql_limit";
}

$data = $this->_query($sql, $system);

// 缓存查询结果
if (is_array($data) && $data) {
    // 系统字段
    $fields['regtime'] = array('fieldtype' => 'Date');
    // 格式化显示自定义字段内容
    $dfield = \Phpcmf\Service::L('Field')->app('member');
    foreach ($data as $i => $t) {
        $data[$i] = $dfield->format_value($fields, $t, 1);
    }

    // 存储缓存
    $system['cache'] && $this->_save_cache_data($cache_name, [
        'data' => $data,
        'sql' => $sql,
        'total' => $total,
        'pages' => $pages,
        'pagesize' => $pagesize,
        'page_used' => $this->_page_used,
        'page_urlrule' => $this->_page_urlrule,
    ], $system['cache']);
}

return $this->_return($system['return'], $data, $sql, $total, $pages, $pagesize);
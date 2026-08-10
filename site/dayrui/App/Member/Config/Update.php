<?php

/**
 * 更新数据结构
 **/

$prefix = \Phpcmf\Service::M()->prefix;

$table = $prefix.'member_setting';
if (!\Phpcmf\Service::M()->db->tableExists($table)) {
    \Phpcmf\Service::M()->query(dr_format_create_sql('CREATE TABLE IF NOT EXISTS `'.$table.'` (
                          `name` varchar(50) NOT NULL,
                          `value` mediumtext NOT NULL,
                          PRIMARY KEY (`name`)
                        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_unicode_ci COMMENT=\'用户属性参数表\';'));
} else {
    if (\Phpcmf\Service::M()->db->fieldExists('id', $table)) {
        // 处理id字段
        $data = \Phpcmf\Service::M()->db->table('member_setting')->get()->getResultArray();
        \Phpcmf\Service::M()->query('DROP TABLE IF EXISTS `'.$table.'`;');
        \Phpcmf\Service::M()->query(dr_format_create_sql('CREATE TABLE IF NOT EXISTS `'.$table.'` (
                              `name` varchar(50) NOT NULL,
                              `value` mediumtext NOT NULL,
                              PRIMARY KEY (`name`)
                            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_unicode_ci COMMENT=\'用户属性参数表\';'));
        if ($data) {
            foreach ($data as $t) {
                \Phpcmf\Service::M()->table('member_setting')->replace([
                    'name' => $t['name'],
                    'value' => $t['value'],
                ]);
            }
        }
    }
}
if (!\Phpcmf\Service::M()->db->table('member_setting')->where('name', 'auth2')->get()->getRowArray()) {
    // 权限数据
    \Phpcmf\Service::M()->query_sql('REPLACE INTO `{dbprefix}member_setting` VALUES(\'auth2\', \'{"1":{"public":{"home":{"show":"0","is_category":"0"},"form_public":[],"share_category_public":{"show":"1","add":"1","edit":"1","code":"1","verify":"1","exp":"","score":"","money":"","day_post":"","total_post":""},"category_public":[],"mform_public":"","form":null,"share_category":null,"category":null,"mform":null}}}\')');
}


$table = $prefix.'member_paylog';
if (\Phpcmf\Service::M()->db->tableExists($table)) {
    if (!\Phpcmf\Service::M()->db->fieldExists('site', $table)) {
        \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `site` INT(10) NOT NULL COMMENT \'站点\'');
    }
    if (\Phpcmf\Service::M()->db->fieldExists('username', $table)) {
        \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` DROP `username`');
    }
    if (\Phpcmf\Service::M()->db->fieldExists('tousername', $table)) {
        \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` DROP `tousername`');
    }
}

$table = $prefix.'member_verify';
if (!\Phpcmf\Service::M()->db->tableExists($table)) {
    \Phpcmf\Service::M()->query("CREATE TABLE IF NOT EXISTS `".$table."` (
    `id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
    `uid` mediumint(8) unsigned NOT NULL COMMENT '会员uid',
    `tid` tinyint(1) unsigned NOT NULL COMMENT '类别',
    `status` tinyint(1) unsigned NOT NULL COMMENT '状态',
    `content` mediumtext NOT NULL COMMENT '自定义字段信息',
    `result` text NOT NULL COMMENT '处理结果',
    `updatetime` int(10) unsigned NOT NULL COMMENT '处理时间',
    `inputtime` int(10) unsigned NOT NULL COMMENT '提交时间',
    PRIMARY KEY (`id`),
    KEY `tid` (`tid`),
    KEY `uid` (`uid`),
    KEY `status` (`status`),
    KEY `inputtime` (`inputtime`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_unicode_ci COMMENT='会员审核表';");
}
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('tid', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `tid` int(1) DEFAULT NULL COMMENT \'类型\'');
}

$table = $prefix.'member_group_verify';
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('price', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `price` decimal(10,2) DEFAULT NULL COMMENT \'已费用\'');
}

$table = $prefix.'member_scorelog';
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('username', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `username` VARCHAR(100) DEFAULT NULL');
}

$table = $prefix.'member_notice';
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('mark', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `mark` VARCHAR(100) DEFAULT NULL');
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$prefix.'member_notice` CHANGE `type` `type` tinyint(2) unsigned NOT NULL COMMENT \'类型\';');
}

$table = $prefix.'member_explog';
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('username', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `username` VARCHAR(100) DEFAULT NULL');
}

$table = $prefix.'member_oauth';
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('unionid', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `unionid` VARCHAR(100) DEFAULT NULL');
}

$table = $prefix.'member_menu';
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('site', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `site` TEXT NOT NULL');
}

$table = $prefix.'member_menu';
if (\Phpcmf\Service::M()->db->tableExists($table) && !\Phpcmf\Service::M()->db->fieldExists('client', $table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `client` TEXT DEFAULT NULL');
}

$table = $prefix.'member_level';
if (\Phpcmf\Service::M()->db->tableExists($table)) {
    \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` CHANGE `stars` `stars` int(10) unsigned NOT NULL COMMENT \'图标\';');
    if (!\Phpcmf\Service::M()->db->fieldExists('setting', $table)) {
        \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `setting` TEXT NOT NULL');
    }
    if (!\Phpcmf\Service::M()->db->fieldExists('displayorder', $table)) {
        \Phpcmf\Service::M()->query('ALTER TABLE `'.$table.'` ADD `displayorder` INT(10) DEFAULT NULL COMMENT \'排序\'');
    }
}
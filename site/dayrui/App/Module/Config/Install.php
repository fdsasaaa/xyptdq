<?php

foreach ($this->site as $siteid) {
    // 防止栏目清空
   // $this->db->simpleQuery("DROP TABLE IF EXISTS `".$this->dbprefix($siteid.'_share_category')."`");
    $this->db->simpleQuery(dr_format_create_sql("
        CREATE TABLE IF NOT EXISTS `".$this->dbprefix($siteid.'_share_category')."` (
          `id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
          `tid` tinyint(1) NOT NULL COMMENT '栏目类型，0单页，1模块，2外链',
          `pid` smallint(5) unsigned NOT NULL DEFAULT '0' COMMENT '上级id',
          `mid` varchar(20) NOT NULL COMMENT '模块目录',
          `pids` varchar(255) NOT NULL COMMENT '所有上级id',
          `name` varchar(255) NOT NULL COMMENT '栏目名称',
          `dirname` varchar(255) NOT NULL COMMENT '栏目目录',
          `pdirname` varchar(255) NOT NULL COMMENT '上级目录',
          `child` tinyint(1) unsigned NOT NULL DEFAULT '0' COMMENT '是否有下级',
          `disabled` tinyint(1) unsigned NOT NULL DEFAULT '0' COMMENT '是否禁用',
          `ismain` tinyint(1) unsigned NOT NULL DEFAULT '1' COMMENT '是否主栏目',
          `childids` text NOT NULL COMMENT '下级所有id',
          `thumb` varchar(255) NOT NULL COMMENT '栏目图片',
          `show` tinyint(1) unsigned NOT NULL DEFAULT '1' COMMENT '是否显示',
          `content` mediumtext NOT NULL COMMENT '单页内容',
          `setting` mediumtext NOT NULL COMMENT '属性配置',
          `displayorder` smallint(5) NOT NULL DEFAULT '0',
          PRIMARY KEY (`id`),
          KEY `mid` (`mid`),
          KEY `tid` (`tid`),
          KEY `show` (`show`),
          KEY `disabled` (`disabled`),
          KEY `ismain` (`ismain`),
          KEY `dirname` (`dirname`),
          KEY `module` (`pid`,`displayorder`,`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='共享模块栏目表';
        "));

    //$this->db->simpleQuery("DROP TABLE IF EXISTS `".$this->dbprefix($siteid.'_share_index')."`");
    $this->db->simpleQuery(dr_format_create_sql("
        CREATE TABLE IF NOT EXISTS `".$this->dbprefix($siteid.'_share_index')."` (
          `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
          `mid` varchar(20) NOT NULL COMMENT '模块目录',
          PRIMARY KEY (`id`),
          KEY `mid` (`mid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='共享模块内容索引表';
        "));
}

file_put_contents(CONFIGPATH.'rewrite.php', file_get_contents(dr_get_app_dir('module').'Config/Rewrite.php'));

file_put_contents(WRITEPATH.'is_module_install.lock', 1);

$json = [];
$json[] = '{"id":"5","type":"3","name":"不带栏目路径","value":"{\"list\":\"list-{dirname}.html\",\"list_page\":\"list-{dirname}-{page}.html\",\"show\":\"show-{id}.html\",\"show_page\":\"\",\"catjoin\":\"/\"}"}';
$json[] = '{"id":"4","type":"3","name":"带栏目路径","value":"{\"list\":\"{dirname}/\",\"list_page\":\"{dirname}/p{page}.html\",\"show\":\"{dirname}/{id}.html\",\"show_page\":\"\",\"catjoin\":\"/\"}"}';
$json[] = '{"id":"8","type":"2","name":"共享模块搜索","value":"{\"search\":\"search/{modname}.html\",\"search_page\":\"search/{modname}/{param}.html\",\"catjoin\":\"/\"}"}';
foreach ($json as $t) {
    $data = dr_string2array($t);
    unset($data['id']);
    $this->table('urlrule')->insert($data);
}

\Phpcmf\Service::M('module', 'module')->install('news', null, 0, 1);

// 默认站点信息字段
$site_field = [];
$site_field['yqlj'] = '{"name":"友情链接","fieldname":"yqlj","fieldtype":"Ftable","isedit":"1","ismain":"1","issystem":"0","ismember":"1","issearch":"0","disabled":"0","setting":{"option":{"is_add":"1","is_first_hang":"0","count":"","first_cname":"","hang":{"1":{"name":""},"2":{"name":""},"3":{"name":""},"4":{"name":""},"5":{"name":""}},"field":{"1":{"type":"1","name":"网站名称","width":"200","option":""},"2":{"type":"1","name":"网站地址","width":"","option":""},"3":{"type":"0","name":"","width":"","option":""},"4":{"type":"0","name":"","width":"","option":""},"5":{"type":"0","name":"","width":"","option":""},"6":{"type":"0","name":"","width":"","option":""},"7":{"type":"0","name":"","width":"","option":""},"8":{"type":"0","name":"","width":"","option":""},"9":{"type":"0","name":"","width":"","option":""},"10":{"type":"0","name":"","width":"","option":""}},"width":"","height":"","css":""},"validate":{"required":"0","pattern":"","errortips":"","xss":"1","check":"","filter":"","tips":"","formattr":""},"is_right":"0"},"displayorder":"0"}';
$site_field['hdtp'] = '{"name":"幻灯图片","fieldname":"hdtp","fieldtype":"Ftable","isedit":"1","ismain":"1","issystem":"0","ismember":"1","issearch":"0","disabled":"0","setting":{"option":{"is_add":"1","is_first_hang":"0","count":"","first_cname":"","hang":{"1":{"name":""},"2":{"name":""},"3":{"name":""},"4":{"name":""},"5":{"name":""}},"field":{"1":{"type":"3","name":"图片","width":"200","option":""},"2":{"type":"1","name":"名称","width":"200","option":""},"3":{"type":"1","name":"跳转地址","width":"","option":""},"4":{"type":"0","name":"","width":"","option":""},"5":{"type":"0","name":"","width":"","option":""},"6":{"type":"0","name":"","width":"","option":""},"7":{"type":"0","name":"","width":"","option":""},"8":{"type":"0","name":"","width":"","option":""},"9":{"type":"0","name":"","width":"","option":""},"10":{"type":"0","name":"","width":"","option":""}},"width":"","height":"","css":""},"validate":{"required":"0","pattern":"","errortips":"","xss":"1","check":"","filter":"","tips":"","formattr":""},"is_right":"0"},"displayorder":"0"}';
foreach ($site_field as $fname => $t) {
    $value = dr_string2array($t);
    if (!$value) {
        continue;
    }
    $value['setting'] = dr_string2array($value['setting']);
    \Phpcmf\Service::M('Field')->relatedid = SITE_ID;
    \Phpcmf\Service::M('Field')->relatedname = 'site';
    if (\Phpcmf\Service::M()->table('field')
        ->where('relatedid', \Phpcmf\Service::M('Field')->relatedid)
        ->where('relatedname', \Phpcmf\Service::M('Field')->relatedname)
        ->where('fieldname', $fname)->counts()
    ) {
        continue;
    }
    $field = \Phpcmf\Service::L('field')->get($value['fieldtype']);
    \Phpcmf\Service::M('Field')->add($value, $field);
}
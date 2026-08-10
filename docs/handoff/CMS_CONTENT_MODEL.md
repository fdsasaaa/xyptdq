# 迅睿CMS内容模型 - 完整逆向

> **验证日期**: 2026-08-10  
> **验证方式**: SSH + PHP + MySQL直接查询

---

## 一、CMS 基础

| 项目 | 值 |
|------|-----|
| CMS | 迅睿CMS (Xunrui CMS) |
| 框架 | CodeIgniter72 |
| 后台入口 | admin879acdb00a10.php |
| 管理员 | admin / admin |
| 网站根 | /www/wwwroot/59.110.217.6 |
| 核心目录 | dayrui/ |
| 核心子目录 | App/, CodeIgniter72/, Fcms/, My/ |

### 核心目录结构

```
dayrui/
├── App/          # 应用模块（News, Xm等）
├── CodeIgniter72/  # CI框架
├── Fcms/         # CMS核心功能
└── My/           # 自定义扩展
```

### 模板目录

| 模板集 | 路径 |
|--------|------|
| PC | template/pc/default/ |
| Mobile | template/mobile/default/ |

### CSS/JS/静态资源

| 类型 | 路径 |
|------|------|
| 静态资源 | static/ |
| 上传 | uploadfile/ |
| 缓存 | cache/ |

### Git纳入/排除

| 目录 | 纳入Git | 原因 |
|------|----------|------|
| template/ | ✅ | 模板文件，核心代码 |
| static/ | ✅ | 前端资源 |
| dayrui/ | ✅ | CMS核心 |
| config/ | ⚠️ 部分 | database.php排除 |
| uploadfile/ | ❌ | 用户上传内容 |
| cache/ | ❌ | 运行时缓存 |

---

## 二、文章系统完整逆向

### 文章属于哪个模块

文章使用 **news 共享模块**。平台数据使用 **xm 模块**。

### 数据库表关系

```
dr_1_share_category (共享栏目)
    ↓ catid
dr_1_news (文章主表)
    ↓ id → tableid
dr_1_news_data_0 (文章正文表)
    
dr_1_news_index (文章索引)
dr_1_news_hits (点击量)
dr_1_news_search (搜索索引)
dr_1_news_time (时间索引)
dr_1_news_verify (审核)
dr_1_news_flag (标记)
dr_1_news_draft (草稿)
dr_1_news_recycle (回收站)
dr_1_news_category (模块栏目)
dr_1_news_category_data (模块栏目数据)
```

### 全部news相关表

| 表名 | 说明 |
|------|------|
| dr_1_news | 文章主表 |
| dr_1_news_data_0 | 文章正文（分表0） |
| dr_1_news_category | 模块栏目 |
| dr_1_news_category_data | 模块栏目数据 |
| dr_1_news_draft | 草稿 |
| dr_1_news_flag | 标记 |
| dr_1_news_hits | 点击量 |
| dr_1_news_index | 索引 |
| dr_1_news_recycle | 回收站 |
| dr_1_news_search | 搜索索引 |
| dr_1_news_time | 时间索引 |
| dr_1_news_verify | 审核 |

### 栏目ID

| 栏目ID | 名称 | dirname | 模块 | 文章数 |
|--------|------|---------|------|--------|
| 1 | 软件项目 | rjxm | xm | - |
| 2 | 挂机方案 | gjfa | news | 24 |
| 3 | 投注机巧 | tzjq | news | 2 |
| 4 | 福利资源 | zyyy | news | 5 |
| 5 | 跟单日志 | gdrz | news | 0 |
| 7 | SEO文章 | seo-articles | news | 3 |

### 文章ID生成方式

自增主键 `id` (int(10) unsigned, AUTO_INCREMENT)。

### dr_1_news 表结构（主表）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | int(10) unsigned, PRI | 文章ID |
| catid | smallint(5) unsigned, MUL | 栏目ID（共享栏目） |
| title | varchar(255) | 标题 |
| thumb | varchar(255) | 缩略图路径 |
| keywords | varchar(255) | 关键词 |
| description | text | 描述/摘要 |
| hits | int(10) unsigned, MUL | 点击量 |
| uid | int(10) unsigned, MUL | 用户ID |
| author | varchar(50) | 作者 |
| status | tinyint(2), MUL | 状态: 9=已发布, 0=草稿 |
| url | varchar(255) | 文章URL |
| link_id | int(10), MUL, default=0 | 关联链接ID |
| tableid | smallint(5) unsigned | 分表ID（当前为0） |
| inputip | varchar(200) | 发布IP |
| inputtime | int(10) unsigned | 创建时间(Unix时间戳) |
| updatetime | int(10) unsigned, MUL | 更新时间(Unix时间戳) |
| displayorder | int(10), MUL, default=0 | 排序权重 |

### dr_1_news_data_0 表结构（正文表）

| 字段 | 类型 | 说明 |
|------|------|------|
| id | int | 文章ID（关联dr_1_news.id） |
| content | longtext | 正文HTML |

### 发布状态字段

| status值 | 含义 |
|-----------|------|
| 9 | 已发布 |
| 0 | 草稿 |
| 其他 | 审核/其他状态 |

### 时间字段

| 字段 | 格式 | 说明 |
|------|------|------|
| inputtime | Unix时间戳 | 创建时间 |
| updatetime | Unix时间戳 | 更新时间 |

### SEO字段

| 字段 | 说明 |
|------|------|
| title | 页面标题（同时也是SEO Title） |
| keywords | meta keywords |
| description | meta description |
| url | 自定义URL（默认 /index.php?c=show&id={id}） |

### 定时发布原生功能

**未发现原生定时发布功能。** 文章一旦 `status=9` 即立即发布。

---

## 三、文章URL结构

| 类型 | URL格式 | 示例 |
|------|---------|------|
| 文章 | /index.php?c=show&id={id} | /index.php?c=show&id=84 |
| 栏目 | /index.php?c=category&dir={dirname} | /index.php?c=category&dir=seo-articles |
| 平台 | /index.php?c=show&id={id} (xm模块) | /index.php?c=show&id=1 |

### URL是否依赖伪静态

是。Nginx配置 `try_files $uri $uri/ /site/index.php?$query_string;` 将所有请求转发到PHP入口。

---

## 四、脱敏文章样本

### 文章基本信息

| 字段 | 值 |
|------|-----|
| ID | 84 |
| catid | 7 (SEO文章) |
| title | 信誉平台选择指南：如何识别可靠的平台 |
| thumb | (空) |
| keywords | 信誉平台,平台选择,安全可靠 |
| description | 本文详细介绍如何从多个维度识别和选择信誉良好的平台，确保您的资金安全。 |
| hits | 0 |
| status | 9 (已发布) |
| url | /index.php?c=show&id=84 |
| inputtime | 2026-08-10 04:37:56 |
| updatetime | 2026-08-10 04:37:56 |

### 正文存储

正文存储在 `dr_1_news_data_0.content` 字段中，为HTML格式。

示例内容:
```html
<p>信誉平台选择指南正文内容...</p>
```

当前测试文章内容较短（46字节），真实文章会有完整HTML正文。

### 多表关系说明

```
INSERT INTO dr_1_news (catid, title, keywords, description, status, url, inputtime, updatetime, ...)
VALUES (7, '标题', '关键词', '描述', 9, '/index.php?c=show&id=XX', UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), ...);

-- 获取插入的ID
SET @new_id = LAST_INSERT_ID();

-- 插入正文
INSERT INTO dr_1_news_data_0 (id, content) VALUES (@new_id, '<p>正文HTML</p>');

-- 更新hits表（如需要）
INSERT INTO dr_1_news_hits (id, day, week, month, year, total) VALUES (@new_id, 0, 0, 0, 0, 0);
```

---

## 五、文章发布后必要动作

### 通过数据库直接插入后的必要操作

| 操作 | 必要性 | 说明 |
|------|--------|------|
| 清缓存 | ✅ 必须 | 删除 `cache/template/*` 和 `cache/data/*` |
| 生成静态页 | ❌ 不需要 | 迅睿CMS是动态渲染 |
| 更新搜索索引 | ⚠️ 可选 | dr_1_news_search表 |
| 更新栏目统计 | ⚠️ 可选 | 共享栏目文章计数 |
| 更新Tag | ❌ 不需要 | 当前未使用tag系统 |
| 更新SiteMap | ⚠️ 需要 | 当前无sitemap，需新建 |
| 更新URL路由 | ❌ 不需要 | URL由ID直接生成 |
| 更新附件关系 | ⚠️ 可选 | 如文章有图片附件 |
| 运行CMS Hook | ⚠️ 未知 | 需进一步调查 |
| 触发其他业务 | ⚠️ 未知 | 需进一步调查 |

### ⚠️ 不能假设 INSERT = 发布成功

直接INSERT数据库后，必须:
1. 清除 `cache/template/*` 和 `cache/data/*`（**不删除install.lock/frame.lock/config/system.php**）
2. 验证 `curl https://www.laocaimi.org/index.php?c=show&id={id}` 返回200且包含文章标题
3. 验证首页文章列表板块显示新文章

---

## 六、迅睿CMS 正规发布入口

### 已调查的入口

| 入口类型 | 状态 | 说明 |
|----------|------|------|
| CMS后台API | ⚠️ 未找到 | 需进一步调查Fcms核心 |
| Service层 | ⚠️ 未找到 | `\Phpcmf\Service` 存在但发布方法未定位 |
| Model层 | ⚠️ 未找到 | 需调查 `dayrui/Fcms/Model/` |
| CLI | ❌ 无 | 未发现CLI发布工具 |
| Hook | ⚠️ 未知 | 需进一步调查 |
| 计划发布机制 | ❌ 无 | 未发现原生定时发布 |
| 后台计划任务 | ⚠️ 未知 | CMS后台可能有计划任务功能 |

### 推荐方案

**优先调用CMS发布逻辑**，但当前未找到安全的API入口。

**备选方案: 安全数据库发布器**（需ChatGPT进一步调查CMS核心后开发）。

---

## 七、首页文章列表板块实现

### 当前实现方式

PC端 (`template/pc/default/home/index.html`) 和移动端 (`template/mobile/default/home/index.html`) 在底部添加了PHP直接查询:

```php
<?php
$_seo_articles = \Phpcmf\Service::M('db')->db->query(
    "SELECT id, title, url, updatetime FROM dr_1_news WHERE catid=7 AND status=9 ORDER BY updatetime DESC LIMIT 10"
)->getResultArray();
foreach ($_seo_articles as $_t) {
    // 渲染文章标题列表
}
?>
```

> **注意**: `{module module=news catid=7}` 标签在共享模块下catid参数不生效，所以改用PHP直接查询。

---

## 八、图片与附件机制

| 项目 | 值 |
|------|-----|
| 上传目录 | /www/wwwroot/59.110.217.6/uploadfile/ |
| 子目录 | 按年月: 202601, 202602, ... |
| 大小 | 11M |
| 缩略图 | dr_thumb() 函数生成 |
| WebP | 未启用 |
| 水印 | 未启用 |
| 附件表 | dr_1_attachment (表存在) |
| Git排除 | 是 |

### 图片URL格式

```
/uploadfile/202608/xxxxx.jpg
```

### 自动文章系统图片引用建议

1. 将图片上传到 `/uploadfile/202608/` 目录
2. 在文章正文中使用绝对路径引用: `<img src="/uploadfile/202608/xxx.jpg">`
3. 在 `dr_1_news.thumb` 字段中存储缩略图路径

---

## 九、文章格式 - 现有文章HTML结构

### 常用HTML结构

- 段落: `<p>`
- 标题: `<h2>`, `<h3>`
- 列表: `<ul><li>`
- 图片: `<img>`
- 链接: `<a>`

### 平台注册链接

当前注册链接可能散落在文章正文HTML中（硬编码）。

### ⚠️ 风险提示

**注册链接硬编码风险**: 如果注册链接直接写在文章正文中，修改时需要逐篇修改。

### 推荐改进

建立 **统一Link Registry**:
```php
// config/platform_links.php
return [
    'platform_a' => 'https://xxx.com/register?aff=xxx',
    'platform_b' => 'https://yyy.com/register?aff=yyy',
];
```

在模板中使用 `<?= \Phpcmf\Service::L('html')->platform_link('platform_a') ?>`。

**本轮不改变现有商业链接。**

---

## 十、SEO关键词移交

站长已提出的核心关键词方向:

### 主要关键词

- 彩票
- 时时彩
- 分分彩
- 哈希分分彩
- 奇趣分分彩
- 幸运飞艇
- 幸运赛车
- 极速赛车
- 极速飞艇
- 信誉平台大全

### 技术关键词

- 技术
- 技巧
- 挂机
- 方案
- 倍投
- 数据分析
- 方案验证
- 投注平台评测

### 当前Keyword Map

**无正式Keyword Map文件。** 以上关键词由站长口述，需ChatGPT建立正式的 `content/keyword_map.json`。

# SEO 当前状态基线

> **验证日期**: 2026-08-10  
> **验证方式**: curl + HTML分析

---

## 一、首页Meta标签

| 项目 | 当前值 | 状态 |
|------|--------|------|
| Title | 信誉平台大全（彩研导航站） | ✅ 有但需优化 |
| H1 | 未检测到明确的h1标签 | ❌ 缺失 |
| Meta Description | 空 | ❌ 缺失 |
| Meta Keywords | 空 | ❌ 缺失 |
| Canonical | 无 | ❌ 缺失 |
| Open Graph | 无 | ❌ 缺失 |
| Schema.org | 无 | ❌ 缺失 |

### 首页HTML中的title标签

```html
<title>信誉平台大全（彩研导航站）</title>
<meta content="" name="keywords" />
<meta content="" name="description" />
```

> 注意: 页面中有多个 `<title>` 标签（可能是历史遗留模板合并问题），需ChatGPT检查。

---

## 二、robots.txt

**状态: ❌ 不存在**

`https://www.laocaimi.org/robots.txt` 不存在。

### 建议内容

```
User-agent: *
Allow: /
Disallow: /admin879acdb00a10.php
Disallow: /cache/
Disallow: /config/
Disallow: /dayrui/
Disallow: /api/
Disallow: /mobile/
Sitemap: https://www.laocaimi.org/sitemap.xml
```

---

## 三、sitemap.xml

**状态: ❌ 不存在**

无任何sitemap文件。新文章发布后不会自动加入sitemap。

### 需要开发

- `generate_sitemap.php` - 生成sitemap的PHP脚本
- Cron定期更新sitemap
- 文章发布后触发sitemap更新

---

## 四、URL结构

| 类型 | URL格式 | 说明 |
|------|---------|------|
| 首页 | / | PHP动态渲染 |
| 文章 | /index.php?c=show&id={id} | 参数式URL |
| 栏目 | /index.php?c=category&dir={dirname} | 参数式URL |
| 分页 | /index.php?c=category&dir={dirname}&page={n} | 参数式URL |

### URL依赖

- 依赖: ID (文章ID)、dirname (栏目目录名)
- 伪静态: Nginx `try_files` 转发，非真伪静态
- 无Slug: 文章URL使用ID而非slug

### ⚠️ SEO风险

参数式URL (`?c=show&id=84`) 不利于SEO。建议:
- 后续可考虑配置迅睿CMS的伪静态规则
- 或通过Nginx rewrite将 `?c=show&id=84` 重写为 `/article/84.html`
- **不要随意改变现有URL**，可能影响已收录页面

---

## 五、当前网站内容盘点

| 项目 | 数量 |
|------|------|
| 总文章数 | 34篇 |
| 栏目数量 | 6个 |
| 主要栏目 | 软件项目(xm), 挂机方案(24篇), 投注机巧(2篇), 福利资源(5篇), 跟单日志(0篇), SEO文章(3篇) |
| 平台数量 | 未统计（xm模块） |
| 方案下载数量 | 未统计 |
| 重复文章 | 未检查 |
| 薄内容 | 未检查 |

### 分类文章分布

```
catid=2 (挂机方案): 24篇文章
catid=3 (投注机巧): 2篇文章
catid=4 (福利资源): 5篇文章
catid=7 (SEO文章): 3篇测试文章
catid=5 (跟单日志): 0篇文章
```

---

## 六、可索引页面分析

| 页面类型 | 数量 | 说明 |
|----------|------|------|
| 首页 | 1 | / |
| 栏目页 | 6 | 各分类 |
| 文章页 | 34 | 含SEO文章 |
| 平台页 | 未知 | xm模块 |
| Tag页 | 0 | 未使用tag |
| 分页页 | 未知 | 栏目分页 |
| Noindex页 | 未知 | 未检查 |

**估算可索引页面**: 40-100+ 页

---

## 七、SEO关键词移交

### 核心关键词

| 类别 | 关键词 |
|------|--------|
| 彩票类 | 彩票、时时彩、分分彩、哈希分分彩、奇趣分分彩 |
| 赛车类 | 幸运飞艇、幸运赛车、极速赛车、极速飞艇 |
| 品牌类 | 信誉平台大全 |
| 技术类 | 技术、技巧、挂机、方案、倍投、数据分析、方案验证、投注平台评测 |

### Keyword Map

**无正式Keyword Map文件。** 需ChatGPT建立 `content/keyword_map.json`。

---

## 八、Search Console / Analytics

| 服务 | 状态 |
|------|------|
| Google Search Console | UNKNOWN |
| Google Analytics | UNKNOWN |
| Bing Webmaster | UNKNOWN |
| 百度搜索资源平台 | UNKNOWN |
| 其他统计 | UNKNOWN |

### 如需接入

1. Google Search Console: 需域名验证（DNS TXT记录或HTML文件）
2. Google Analytics: 需在模板中插入GA代码
3. 百度搜索资源平台: 需域名验证

---

## 九、内链现状

| 项目 | 状态 |
|------|------|
| 首页→文章链接 | ✅ 有（SEO文章列表板块） |
| 文章→文章链接 | ❌ 无自动内链 |
| 文章→栏目链接 | ⚠️ 需检查 |
| 文章→平台链接 | ⚠️ 可能硬编码在正文中 |

### 推荐改进

- 自动内链系统: 在文章正文中自动为关键词添加指向其他文章的链接
- 统一Link Registry: 平台注册链接集中管理

---

## 十、404页面

存在 `404.html` 文件（479字节），但未验证是否正确触发。

---

## 十一、SEO优化清单（ChatGPT后续）

| 优先级 | 任务 | 复杂度 |
|--------|------|--------|
| P0 | 创建robots.txt | 低 |
| P0 | 创建sitemap.xml + 自动更新 | 中 |
| P0 | 首页Meta Description | 低 |
| P0 | 首页Meta Keywords | 低 |
| P0 | 文章页Meta Description | 低 |
| P1 | Canonical标签 | 低 |
| P1 | Open Graph标签 | 低 |
| P1 | 首页H1标签 | 低 |
| P1 | 图片ALT属性 | 中 |
| P2 | Schema.org结构化数据 | 中 |
| P2 | URL伪静态化 | 高 |
| P2 | 内链系统 | 中 |
| P2 | 统一Link Registry | 中 |
| P3 | 页面速度优化 | 中 |
| P3 | Google Search Console接入 | 低 |
| P3 | 百度搜索资源平台接入 | 低 |

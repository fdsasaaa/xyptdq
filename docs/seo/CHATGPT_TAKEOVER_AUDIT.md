# ChatGPT SEO 接管审计

日期：2026-08-10

## 当前接管结论

已读取 WorkBuddy 移交包并直接复核 GitHub 生产基线代码。

### P0：必须优先修复

1. 首页模板 `site/template/pc/default/home/index.html` 当前包含 `<meta name="robots" content="none">`。对遵循 robots meta 的搜索引擎而言，这会阻止索引/跟踪，和 SEO 目标直接冲突。
2. 同一首页模板中存在多个完整 HTML 文档片段、多个 `<!DOCTYPE html>`、`<head>` 和 `<title>`，必须整理为单一合法文档结构，避免搜索引擎解析歧义。
3. 当前没有 `robots.txt` 和 `sitemap.xml`。本分支已先加入可部署的 `site/robots.txt`；sitemap 生成器待下一步实现。

### P1：随后完成

- 首页唯一 H1、Meta Description、Canonical、Open Graph。
- 文章页/栏目页 Canonical 与结构化数据。
- Keyword → URL Mapping。
- Sitemap 自动生成与文章发布后更新。
- 内链体系与平台链接 Registry。
- 100+ 文章库存的 Article Queue、幂等发布器和定时发布。

## GitHub / 部署判断

ChatGPT 已能通过 GitHub 连接直接创建分支与提交文件，因此用户无需把 GitHub Token 明文发送给 ChatGPT。

真正尚未打通的是 GitHub → 生产服务器的无人值守部署链路。生产服务器当前没有 Git 仓库认证，部署脚本也没有端到端验证。

## 安全提醒

移交资料中出现了 CMS 后台登录凭据描述；此前 SSH root 密码也曾在聊天中以明文出现。正式自动化部署稳定后，应轮换这些凭据，并改用 SSH Key / 最小权限部署账户，任何新 Secret 均不得进入 Git 历史。

## 下一执行顺序

1. 修正首页 robots/noindex 与重复 HTML 结构。
2. 建立 sitemap 生成器。
3. 建立 SEO keyword map 与专题架构。
4. 建立自动发布 Article Queue。
5. 建立一次性服务器 bootstrap，使 GitHub 版本可安全部署到生产。
6. 部署后做真实 HTTP/SEO 健康检查，再进入批量内容生产。

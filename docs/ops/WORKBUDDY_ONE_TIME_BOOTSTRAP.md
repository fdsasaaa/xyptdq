# WorkBuddy 一次性生产环境收尾任务

> 目标：完成 ChatGPT 无法直接通过 SSH 执行的最后一段服务器侧工作。完成后，WorkBuddy 不再参与日常 SEO、内容生产和普通网站修改。

## 任务边界

本轮只允许完成：安全凭据轮换、GitHub 生产副本建立、SEO P0 上线、发布链路只读探针、备份定时化以及确定性自动化所需的服务器准备。

禁止本轮大规模改版、批量发文章、升级 CMS/PHP/MariaDB、删除旧内容或重构数据库。

## 0. 安全门

1. 先建立新的完整生产备份并验证校验值。
2. 记录当前网站首页 HTTP 200、Nginx/PHP-FPM/MariaDB 状态。
3. 所有 Secret 只在服务器本地处理，禁止输出到聊天、GitHub、日志或 PR。
4. 任何一步验证失败，停止后续生产写操作并回滚本步骤。

## 1. 立即处理已暴露凭据

GitHub 曾经追踪过生产 `site/config/database.php`；该文件已经从最新 main 删除并加入 `.gitignore`，但旧 Git 历史可能仍可访问。因此必须把旧数据库密码视为已经泄露。

执行：

- 识别生产 CMS 实际使用的数据库账号和 Host 匹配规则；
- 在服务器本地生成高强度新密码，不向外输出；
- 用 MariaDB 支持的正规方式轮换该账号密码；
- 原子更新生产 `config/database.php`；
- 验证 CLI 数据库连接、首页、文章页、后台均正常；
- 若失败，立即使用本地备份恢复旧配置并停止。

此前 root 密码和 CMS 后台凭据也曾通过非 Secret 渠道传递。先建立并验证备用安全登录方式后，再轮换 root 密码。CMS 管理员密码应通过迅睿 CMS 正规密码修改/重置机制轮换，不要猜测密码哈希算法直接改表。

最终报告只能写：`ROTATED / NOT ROTATED / BLOCKED`，不得显示任何新旧密码。

## 2. 建立服务器上的正式 Git 工作副本

仓库：`fdsasaaa/xyptdq`

目标路径建议：`/opt/xyptdq-repo`

要求：

- 不把生产 WebRoot 本身直接变成 Git 工作树；
- clone/fetch 后固定验证远端仓库名和 main；
- 当前 main 至少应包含 ChatGPT SEO foundation 合并提交；
- Git 工作副本不得保存数据库密码、SSH 私钥副本或其他运行时 Secret；
- 若仓库仍为 public，可先使用 HTTPS 只读 clone；若仓库已改 private，则配置只读 Deploy Key，不使用写权限 Token 写在 remote URL 中。

不要让服务器具备不必要的 GitHub 写权限。

## 3. SEO P0 生产修复

从 main 获取并验证以下工具：

- `site/robots.txt`
- `scripts/seo/patch_homepage_noindex.php`
- `scripts/seo/generate_sitemap.php`
- `scripts/health-check.sh`

执行顺序：

1. 再确认生产首页 PC 模板仍只存在一个精确的 `<meta name="robots" content="none">`；
2. 先运行 patcher 的 check-only 模式；
3. 只有 check 输出“exactly one legacy tag”时才带 `--apply`；
4. 将 `site/robots.txt` 部署到 WebRoot；
5. 运行 Sitemap 生成器；
6. 安全清理模板/数据缓存；
7. 验证 `https://www.laocaimi.org/robots.txt` 返回 200；
8. 验证 `https://www.laocaimi.org/sitemap.xml` 返回 200 且 XML 可解析；
9. 验证生产首页最终 HTML 不再包含 `robots=none/noindex`；
10. 验证首页、至少一个栏目页、至少一个文章页仍返回 200。

注意：PC 首页模板还存在多个 DOCTYPE/head/title 的历史结构问题。本轮不要盲目整页重写；只做可证明安全的 robots P0 修复。结构重构留给 ChatGPT 后续通过版本化修改完成。

## 4. 执行 CMS 发布链路只读探针

自动文章发布当前刻意保持 WRITE LOCKED。

必须选择一篇“确认由迅睿 CMS 后台正常发布”的普通 news 文章作为样本，而不是仅凭猜测使用某个测试 ID。

执行：

`php scripts/content/publisher_probe.php --article-id=<KNOWN_GOOD_ID> --output=/tmp/xyptdq-publisher-probe.json`

检查输出：

- 不包含密码、Token、私钥；
- 列出 `dr_1_news*` 相关表结构和该文章在各表中的对应行；
- content 只保留长度/hash，不保留全文。

将脱敏后的探针结果提交到新分支：

`ops/publisher-probe-YYYYMMDD`

路径：

`docs/probes/publisher_probe_known_good.json`

然后创建 PR，不合并，等待 ChatGPT读取并完成真正的 CMS 写适配器。

禁止本轮直接打开 `auto_publish.php --commit`。

## 5. 验证 SQLite 能力

执行：

- `php -m` 检查 `pdo_sqlite`；
- 若已安装，记录 `AVAILABLE`；
- 若未安装，只记录 `MISSING`，不要为了本轮擅自升级 PHP；可安装与 Ubuntu 20.04/PHP 7.4 完全匹配的小版本扩展前，必须先评估对生产 PHP-FPM 的影响。

不要因为缺少 SQLite 就改为未经验证的数据库队列表。

## 6. 定时备份

当前备份脚本已存在，但必须先验证最新 main 中脚本与服务器实际环境一致。

只在备份脚本真实成功并产生可校验文件后，配置每天一次定时备份。建议本地时区凌晨低峰期执行。

同时建立保留策略，避免磁盘无限增长。例如保留最近 14 个日备份 + 4 个周备份，具体按实际备份大小和剩余空间核算。

不要在没有保留策略的情况下无限 cron 备份。

## 7. 不要开启无人值守生产部署，先做 preflight

本仓库历史 `deploy.sh/rollback.sh` 尚未完成生产端到端验证，而且 deploy 使用 `rsync --delete`。本轮只验证其输入/排除规则，不直接把“自动拉取 main 后立即 rsync --delete”设成 cron。

需要确认至少：

- `uploadfile/` 保留；
- `cache/` 不由 Git 覆盖；
- 生产 `config/database.php` 保留；
- `.user.ini` 等服务器专用文件保留；
- 其他迅睿 CMS 运行时生成文件不会被 `--delete` 误删；
- 部署前备份能成功；
- health-check 能真实返回正确状态。

输出一份 `DEPLOY_PREFLIGHT_RESULT.md` 到 `docs/probes/`，提交到与 publisher probe 相同的 PR。

在 ChatGPT 阅读并修正 deploy 规则以前，不配置自动生产部署。

## 8. 最终交付给 ChatGPT

最终只回复用户一个脱敏状态摘要，并把详细证据提交 GitHub PR。摘要格式：

```text
【一次性服务器收尾】
Backup: PASS/FAIL
DB credential rotation: ROTATED/BLOCKED
Root credential rotation: ROTATED/BLOCKED
CMS admin credential rotation: ROTATED/BLOCKED
Server Git working copy: READY/BLOCKED
robots.txt production: PASS/FAIL
Homepage indexing block: REMOVED/NOT REMOVED
sitemap.xml: PASS/FAIL + URL count
pdo_sqlite: AVAILABLE/MISSING
Scheduled backup: ENABLED/NOT ENABLED
Publisher probe: PASS/FAIL
Deploy preflight: PASS/FAIL
Probe branch: ...
PR: ...

【Secrets】
No secret values disclosed: YES/NO

【Blocking items】
...
```

不要把任何凭据值贴回聊天。完成后等待 ChatGPT继续接管。

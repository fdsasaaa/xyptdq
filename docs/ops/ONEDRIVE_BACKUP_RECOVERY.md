# OneDrive 每日备份与新服务器恢复

实施总记录：[Issue #509](https://github.com/fdsasaaa/xyptdq/issues/509)。机器入口：`backups-manifest/CURRENT.json`。

## 已知状态与完成标准

2026-11-01 的生产只读探测已通过：网站目录 45,244,377 字节；内容队列 13,420,026 字节；发布台账 68,878 字节；代码目录 54,549,593 字节；空闲磁盘约 27GB。五项 CMS 必需文件均存在。原服务器时区 UTC，新的每日任务明确采用 Asia/Shanghai。

探测时没有 restic/rclone，没有 OneDrive 配置，也没有每日备份 timer。这些数值是探测时的状态，不代表部署后状态。后续以 #509 和生产任务回执为准。

2026-11-01 08:58（北京时间）生产准备已 PASS：已部署工具/程序，创建 110,985,974 字节的本地恢复载荷，必要文件与全量 SHA-256 通过，本地 Restic 加密备份/还原/读取校验通过。云端快照和每日 timer 仍未创建。回执保存在 `backups-manifest/evidence/20261101-server-preparation.json`。

为避免长期使用旧系统仓库中的历史工具，另行固定官方 rclone v1.75.2 与 Restic v0.19.1 Linux amd64 二进制，安装前校验各自 GitHub 官方 release asset 的 SHA-256，安装后重新进行加密恢复往返测试。具体升级结果以对应生产任务回执为准；后续升级必须重新固定版本和校验值，不使用未经校验的网络安装脚本。

必须区分：脚本入库、工具部署、本地副本、微软授权、远程快照、下载校验、新主机完整恢复演练、每日任务成功。只有真实远程 snapshot ID 加下载验证通过，才能宣称 OneDrive 备份成功；只有 timer 激活且出现定时运行回执，才能宣称每日备份生效。

## 保存位置与范围

- GitHub：恢复程序、说明、非敏感状态入口和实施记录。整站数据、SQL、OAuth 配置和密钥不得提交到这个公共仓库。
- OneDrive 默认路径：`WebsiteBackups/xyptdq/restic-v1`，为加密且去重的 Restic 仓库。
- OneDrive 状态索引：同级 `restic-v1-inventory/status.json`。完整时间点清单以 `restic snapshots` 为准；该索引不含文章正文、密码或网盘登录资料。
- 服务器：`/etc/xyptdq-backup/config.json`、`rclone.conf` 和 `repository-password`，root 所有、0600。私有工作目录 `/var/lib/xyptdq-backup`，0700。
- 程序固定安装在 `/usr/local/lib/xyptdq-backup`，不随发布器 `git reset` 改变；升级要明确部署新版本。

每个快照含：完整网站和上传（保留 `cache/frame.lock`、`cache/install.lock`、`cache/config`、`cache/data`）；MariaDB SQL（含触发器、事件和存储过程）；`/var/lib/xyptdq-content` 和 `/var/lib/xyptdq-publisher`；生产代码工作树及独立 Git bundle；Nginx/PHP/MariaDB/cron/systemd/证书配置；根用户 crontab；运行环境、源代码 SHA 与文件 SHA-256 清单。

不备份可再生的模板编译缓存、session 和日志缓存；不将网盘授权配置和加密密码收入恢复载荷。线上应用配置含敏感内容，因此整个恢复载荷只上传到加密仓库。

SQL 使用本机管理员 socket 认证并短暂加全局读锁，兼容事务表及 MyISAM。备份期间现有发布/入库 flock 被持有；遇到正运行的任务会失败并稍后重试。手工后台编辑和外部上传仍然是实时的，因此这不是原子磁盘镜像；重要迁移前应短暂进入维护窗口，冻结写入再生成最终快照。

## 首次配置（一次性）

### 推荐的浏览器授权入口：SSH 隧道

用户电脑的 OpenSSH 已确认可用时，由固定 SHA 的 `prepare_onedrive_ssh_v1.sh` 部署 `authorize_ssh.py` 并返回生产服务器的 ED25519 指纹、SSH端口与登录方式。该任务不启动过期计时中的授权会话，不修改 SSH 配置。

用户在自己的 Windows PowerShell 通过 SSH 转发本机 `127.0.0.1:53682` 到服务器相同回环地址，同时运行服务器上的 `python3 /usr/local/lib/xyptdq-backup/authorize_ssh.py`。先核对本次探测的主机指纹，再使用用户已有的 SSH 登录方式；SSH 密码只在本机终端输入。

连接后程序会在用户自己的 SSH 终端显示一次性回环登录链接。用户用本机浏览器打开，登录拥有备份空间的微软账号并授权；完整回调/令牌直接回到服务器，用户不需要复制令牌到聊天。单个云盘自动选定；多个云盘由用户在自己的SSH终端明确选择。所有原始日志/配置仅存服务器私有目录，公开回执只含阶段、云盘类型和容量数字。

授权程序只监听服务器回环地址，无公网授权端口；SSH断开或20分钟超时会清理子进程。成功后通过 `rclone about` 验证容量，非敏感结果可从 `/uploadfile/xyptdq-agent-results/onedrive-oauth-status.json` 读取。成功授权不等于已有备份：仍须完成加密密码独立保管、首次远端快照、下载验证、timer 激活及定时运行验证。原 `onedrive-setup.json` 是此前无浏览器流程的状态，不应据其旧问题推断当前授权是否完成。

2026-11-01第一轮SSH授权在20分钟等候后返回 `LOGIN_TIMED_OUT_RERUN_SSH_COMMAND`，没有保存可用token/drive。用户只看到登录链接时，不应将其记录为授权完成。后续Windows连接建议使用 `-L localhost:53682:127.0.0.1:53682`，兼容微软回调localhost的IPv4/IPv6，并设置 `ServerAliveInterval=20`。可在本机PowerShell逐行显示SSH输出，只对白名单 `http://127.0.0.1:53682/auth?state=<URL-safe-value>` 自动调用默认浏览器；最终仍由用户在微软网页登录并同意。终端显示“授权完成，OneDrive容量校验通过”才算完整结束。

原一次性grant已在启动第一轮助手前消费；超时后用相同用户公钥和新grant-id恢复入口，不要求用户重建私钥，也不复用旧OAuth链接。`renew_onedrive_auth_key_v1.sh` 会保留已经配置好的连接，并在仍有授权监听器时停止重发，避免打断活跃会话。

多个云盘还可由 `finalize_default_onedrive_v1.sh` 核对 Microsoft Graph `/me/drive` 返回的本人默认 OneDrive。仅在其 ID 与 rclone 候选值唯一匹配、类型为 personal/business 时继续，不按候选顺序猜测，不选择共享文档库；公开结果只含容量和是否匹配。只有确认原助手仍停在同一个选择状态时，才结束该助手并接管其配置锁。

### 临时 SSH 公钥入口

若用户无法使用原 SSH 密码，可由用户在本机生成 Ed25519 临时密钥，只提供 `.pub` 公钥。经用户提供并核对指纹后，固定 SHA 的任务将它加入原有 `authorized_keys`，保留全部原条目；限制为指定授权助手以及127.0.0.1:53682的转发，禁止普通shell/PTY/代理/X11/用户rc，设置两小时有效期。OpenSSH8.2的 `expiry-time` 使用服务器本地14位日期时间，不使用新版的Z后缀。

入口为 `/usr/local/lib/xyptdq-backup/limited_ssh.py use <grant-id>`，它在启动OAuth助手前移除自己对应的授权条目并记录已消费；不恢复整份旧 `authorized_keys`，不修改密码或全局SSH配置。若尝试已消费或到期，必须通过新任务明确重发新grant，不能把失败误判为服务器原密码又出错。未使用的条目到期后会被sshd拒绝，后续清理记录时只删除本项目标记的对应条目。用户连接应明确指定本机私钥、IdentitiesOnly及BatchMode，避免回退到服务器密码登录。

### 初始化与首次备份

1. 运行固定 SHA 的 `prepare_onedrive_backup_v1.sh` 生产任务，安装工具、部署程序、创建受保护的随机加密密码，生成并校验一份本地恢复载荷。它不启用 timer，不创建云端备份。
2. 用户在微软官方登录页面完成 rclone 的 OneDrive OAuth 授权，配置名为 `onedrive`，配置文件仅放在服务器 `/etc/xyptdq-backup/rclone.conf`。不要把授权结果、token 或配置内容贴到 GitHub/聊天/公开任务回执。无浏览器服务器依照 rclone 官方 headless OAuth 流程在有浏览器的设备授权，通过安全文件传输交给服务器。
3. 用 `rclone --config /etc/xyptdq-backup/rclone.conf about onedrive: --json` 私下核对账户及容量。确保是用户长期控制且可恢复登录的账号。
4. 配置文件与密码设置为 root:root、0600，配置目录0700。对新仓库执行以下首次备份步骤；自动化首次任务会先确认目标为空，已有仓库则校验原仓库和密码，不重复初始化：

```bash
sudo python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py init
sudo python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py backup
sudo python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py snapshots
```

`init` 仅限新仓库；已有仓库须使用原密码，不得重建或覆盖。`backup` 会下载同一个 snapshot 到私有目录并校验全部载荷后才记录成功。

### 独立保存恢复文件与启用每日任务

首次云快照下载验证后，`prepare_recovery_export_v1.sh` 可以对同一用户公钥签发 `export_recovery` 专用的一次性grant。此用途没有任何端口转发权；仅允许 `SSH_ORIGINAL_COMMAND=export-recovery-key`，错误的远程命令会在消费grant前被拒绝，避免用户重跑旧授权命令时把恢复密码输出到终端。

用户通过SSH将单行恢复JSON直接保存到本机 `%LOCALAPPDATA%/XYPTDQ-BackupRecovery`，使用UTF-8无BOM和LF换行；不在控制台显示内容。JSON含仓库路径、`repository_password`、源码仓库和手册入口。服务器在私有grant记录中保留文件SHA-256与字节数，核对用户本机文件的SHA-256即可确认传输一致，不需要用户把内容发给ChatGPT或公共GitHub。

这个文件必须独立于原服务器保管，建议另放用户自己的密码管理器或离线介质。文件内容不进入聊天、公开回执或Git仓库。新主机恢复时，从JSON的 `repository_password` 写入受保护的Restic密码文件，并重新授权同一OneDrive；已有仓库不可再次init。只有网盘账号而没有此密码无法恢复。

核对独立恢复文件的 SHA-256 后，再执行 `sudo bash /usr/local/lib/xyptdq-backup/install_timer.sh`。安装程序本身拒绝在没有近期成功备份时启用；自动部署任务还必须核对私有导出记录与用户回报的文件哈希，再记录独立保管确认。

每日北京时间 03:30 执行，最多延迟5分钟；服务器关机错过后会补跑；失败15分钟后重试，2小时内最多3次。运行在网站服务器，用户电脑可以关机，不使用 GitHub Actions 上传整站。

## 日常检查与保留

```bash
sudo python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py status
sudo systemctl status xyptdq-backup.timer xyptdq-backup.service
sudo journalctl -u xyptdq-backup.service --since '2 days ago'
sudo python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py check
```

`status` 超过36小时无成功快照或最近一次失败会返回非零；失败不会抹掉之前的成功时间。原始日志只留服务器。完整 `check` 读取远端数据，定期及迁移前执行。日志/非零状态尚不等同于用户已收到外部告警；外部停机/过期告警渠道需要另行配置并验证，不能只依靠已停机服务器自己告警。

初期保留所有快照，不自动删除旧备份。完成独立恢复演练并确认空间后，再显式配置30个日版本、12个周版本、12个月版本的 `restic forget --keep-daily 30 --keep-weekly 12 --keep-monthly 12`；删除操作必须限制本网站 host/tag 并先预览。不要对 Restic 仓库使用同步删除，也不要直接改动其 data/index 文件。

## 指定日期恢复 / 迁移到新主机

新主机必须能运行此 CMS 的兼容 PHP、扩展、MariaDB 和 Nginx。共享空间如果没有 shell、数据库导入或对应 PHP 能力，需要使用其控制面板迁移接口，不能保证任意服务商都能用同一个命令安装。依赖版本记录在快照 `environment.json` 中。

1. 在新主机取得本 GitHub 仓库的恢复程序。即使 GitHub 不可用，载荷中的 `source.bundle` 仍可恢复备份时的代码；预先保存本手册和恢复程序副本。
2. 安装 restic/rclone，重新授权同一个 OneDrive，放入独立保管的原加密密码；配置指向现有仓库。**不要再次 init。**
3. 列出快照，根据 UTC 时间选择具体 ID，不将代码提交时间当成数据备份时间：

```bash
sudo python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py snapshots
sudo python3 /usr/local/lib/xyptdq-backup/onedrive_backup.py restore --snapshot <snapshot-id> --target /srv/xyptdq-restore-YYYYMMDD
```

`--snapshot latest` 表示本网站最后一个快照。目标必须为空，下载后验证所有 SHA-256、载荷和 CMS 标记；输出 `RESTORE_VERIFIED.json` 仅表示下载校验，不表示已导入数据库或上线。

4. 在还原出的 `manifest.json` 读取原数据库名、原网站路径、代码版本。先在隔离环境准备空数据库和目标目录。调用 `safe_members` 或等效审查，确认 website/runtime 归档无绝对路径、穿越、设备或未审查的链接后再解包。不要将 `system.tar` 不加检查覆盖新主机的 `/etc`。
5. 将 `website.tar` 还原到新的 webroot，保留必需 cache 配置/锁文件。建立新的数据库与专用账号，导入 `database.sql`，同步修改实际 `config/database.php` 的主机、数据库和凭据（不要输出凭据）。配置 PHP-FPM 用户、上传/缓存写权限。
6. 从 bundle 恢复同版本源码，例如 `git clone /私有还原路径/source.bundle /opt/xyptdq-repo`。把 runtime 中的内容队列、发布台账、收据还原到选定的新路径。相应脚本/环境变量和定时任务必须同步改路径。
7. 以归档配置与 `infra/nginx_site.conf` 为参考生成新站点配置，调整 webroot、PHP socket、域名、上传目录 PHP 禁执行和入口重写；校验证书和到期日，必要时重新签发 HTTPS。不得直接沿用旧 IP。
8. 在切换 DNS 前，通过 hosts/`curl --resolve` 测试首页、文章、栏目、移动端、图片/附件、后台登录、canonical/301/robots/sitemap。将恢复快照和通过的 URL/检查记录到 #509 或新的迁移 Issue。
9. 自动发布任务、入库任务和 Server Bridge 默认不启用。原主机仍可运行时，先停其写入任务，补最终快照、导入最终增量，再切换 DNS；确认仅一个主机执行任务后才恢复调度。
10. 新主机重新执行云备份及下载校验，重新安装每日备份 timer，完成首次定时运行验证，记录新路径和恢复结果。

“接近一键”的验收终点是上述实际恢复并上线检查全部通过，而非只是一个安装脚本退出零。当前没有新服务器完整恢复成功证据。

## 每次实施必须更新的记录

记录实施 Issue/PR、程序 commit、实际状态、首个与最新成功 snapshot ID/时间、远端仓库非敏感路径、保留策略、校验/演练结果、最后成功定时运行、新主机路径和待办。权限和密钥只记录存放位置；不记录内容。每天的数据清单在加密 snapshot 中，OneDrive 独立状态索引保存最近成功回执；GitHub 不积累整站压缩包。

官方参考：[Restic rclone 后端](https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html#other-services-via-rclone)、[rclone OneDrive](https://rclone.org/onedrive/)、[无浏览器授权](https://rclone.org/remote_setup/)。

# 当前生产环境基线 (CURRENT_PRODUCTION_BASELINE)

> 生成时间: 2026-08-10
> 生成者: WorkBuddy 网站总控

## 服务器

| 项目 | 值 |
|------|------|
| IP | 94.103.5.248 |
| SSH端口 | 22 |
| 操作系统 | Ubuntu 20.04.6 LTS (Focal Fossa) |
| 内核 | 5.4.0-216-generic |
| CPU | Intel Xeon (Cascadelake) 2核 |
| 内存 | 2.0 GB |
| 磁盘 | 39GB (使用29%) |
| 文件系统 | ext4 |
| 时区 | Etc/UTC |
| 运行时间 | 259天 |

## Web环境

| 组件 | 版本 |
|------|------|
| Nginx | 1.18.0 (Ubuntu) |
| PHP | 7.4.3-4ubuntu2.29 |
| PHP-FPM | 7.4 (unix socket: /run/php/php7.4-fpm.sock) |
| Python | 3.8.10 |
| Node.js | 未安装 |

## 数据库

| 组件 | 版本 |
|------|------|
| MariaDB | 10.3.39 |
| 绑定地址 | 127.0.0.1:3306 |
| 数据库 | dayrui, wordpress, wpdb |
| dayrui用户 | dayruiuser |
| 表前缀 | dr_ |

## 管理面板

无（纯SSH管理）

## 网站信息

| 项目 | 值 |
|------|------|
| CMS | 迅睿CMS (Xunrui CMS) |
| 框架 | CodeIgniter |
| 网站根目录 | /www/wwwroot/59.110.217.6 |
| Canonical域名 | https://www.laocaimi.org |
| xyptdq.com | NXDOMAIN（公共DNS无记录） |
| laocaimi.org | A记录 → 94.103.5.248 |
| www.laocaimi.org | A记录 → 94.103.5.248 |

## Nginx配置

- 主配置: /etc/nginx/nginx.conf
- 站点配置: /etc/nginx/sites-available/site.conf → sites-enabled/
- 端口: 80(HTTP→301), 443(SSL)

## SSL证书

| 证书名 | 域名 | 状态 |
|--------|------|------|
| laocaimi.org | laocaimi.org, www.laocaimi.org | ✅ 有效 (至2026-11-08) |
| ~~xyptdq.com~~ | ~~xyptdq.com~~ | ❌ 已删除 (域名NXDOMAIN) |
| ~~www.xyptdq.com~~ | ~~www.xyptdq.com~~ | ❌ 已删除 (域名NXDOMAIN) |

- 证书路径: /etc/letsencrypt/live/laocaimi.org/
- 自动续期: certbot.timer (systemd)
- 续期方式: nginx authenticator

## 防火墙 (UFW)

| 端口 | 协议 | 状态 |
|------|------|------|
| 22 | SSH | ALLOW |
| 80 | HTTP | ALLOW |
| 443 | HTTPS | ALLOW |

## 目录结构

```
/www/wwwroot/59.110.217.6/     ← 生产网站根目录 (Nginx root)
├── index.php                   ← 迅睿CMS入口
├── admin879acdb00a10.php       ← 后台入口(随机名称)
├── config/                     ← CMS配置
│   └── database.php            ← 数据库配置(含密码，不提交)
├── dayrui/                     ← CMS核心
├── template/                   ← 网站模板
├── static/                     ← 静态资源
├── mobile/                     ← 移动端模板
├── uploadfile/                 ← 用户上传(不提交)
├── cache/                      ← 缓存(不提交)
├── api/                        ← API
└── xdb/                        ← 数据辅助

/var/www/wordpress/             ← WordPress (未启用，遗留)
/www/wwwroot/xyptdq.com/        ← WordPress (未启用，遗留)
/root/xyptdq.com/               ← WordPress (未启用，遗留)
/var/www/releases/              ← 旧发布版本
```

## 系统服务

| 服务 | 状态 |
|------|------|
| nginx | active (running) |
| php7.4-fpm | active (running) |
| mariadb | active (running) |
| certbot.timer | active |
| ufw | active |

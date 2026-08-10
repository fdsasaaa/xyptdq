# 系统状态 - 生产服务器

> **验证日期**: 2026-08-10  
> **验证方式**: SSH直接检查

---

## 一、操作系统

| 项目 | 值 |
|------|-----|
| 发行版 | Ubuntu 20.04.6 LTS (Focal Fossa) |
| 内核 | 5.4.0-216-generic |
| 主机名 | green-clusters-1.localdomain |
| 运行时间 | 259天 |
| 内存 | 2.0Gi total, 391Mi used, 1.4Gi available |
| 磁盘 | /dev/sda3 39G, 11G used, 27G free (29%) |
| 负载 | 0.06, 0.03, 0.01 |

---

## 二、Web Server

| 项目 | 值 |
|------|-----|
| 软件 | Nginx 1.18.0 (Ubuntu) |
| 配置测试 | syntax is ok, test is successful |
| 启用站点 | site.conf |
| 配置路径 | /etc/nginx/sites-enabled/site.conf |
| 日志 | /var/log/nginx/access.log, error.log |

### Nginx 配置要点

- HTTP 80端口 → 301重定向到 `https://www.laocaimi.org`
- HTTPS 443端口 → SSL证书 laocaimi.org
- root: /www/wwwroot/59.110.217.6
- index: index.php index.html
- try_files: `$uri $uri/ /site/index.php?$query_string`
- PHP-FPM: `unix:/run/php/php7.4-fpm.sock`
- `fastcgi_param HTTPS on;` — 关键，告诉PHP当前是HTTPS
- HSTS: `max-age=31536000`
- ACME challenge路径已放行（用于SSL续期）
- `.php` in uploadfile/cache/static 目录被禁止执行
- 隐藏文件 `~ /\.` 被deny

### 域名重定向链

```
http://laocaimi.org → https://www.laocaimi.org (301)
http://www.laocaimi.org → https://www.laocaimi.org (301)
https://laocaimi.org → https://www.laocaimi.org (301 or redirect)
https://www.laocaimi.org → 正常服务 (200)
```

---

## 三、PHP

| 项目 | 值 |
|------|-----|
| 版本 | PHP 7.4.3-4ubuntu2.29 (NTS) |
| FPM状态 | active (running), enabled |
| Socket | /run/php/php7.4-fpm.sock |
| 所有者 | www-data:www-data |

---

## 四、数据库

| 项目 | 值 |
|------|-----|
| 类型 | MariaDB |
| 版本 | 10.3.39 |
| 状态 | active (running), enabled, 8个月15天 |
| 监听 | 127.0.0.1:3306 (本地) |
| 数据库名 | dayrui |
| 用户名 | dayruiuser |
| 密码 | 已配置（在database.php中） |
| 表前缀 | dr_ |

### 配置文件路径

```
/www/wwwroot/59.110.217.6/config/database.php
```

格式:
```php
$db['default'] = [
    'hostname' => '127.0.0.1',
    'username' => 'dayruiuser',
    'password' => '***',
    'database' => 'dayrui',
    'DBPrefix' => 'dr_',
];
```

---

## 五、CMS - 迅睿CMS

| 项目 | 值 |
|------|-----|
| CMS | 迅睿CMS (Xunrui CMS) |
| 框架 | CodeIgniter72 |
| 网站根目录 | /www/wwwroot/59.110.217.6 |
| 后台入口 | admin879acdb00a10.php |
| 管理员 | admin / admin |

### 根目录结构

```
/www/wwwroot/59.110.217.6/
├── 404.html
├── admin879acdb00a10.php     # 后台入口（隐藏）
├── api/
├── cache/                     # 缓存目录（关键）
│   ├── install.lock          # CMS已安装标记（内容: 2026-02-03 04:14:00）
│   ├── frame.lock             # 框架选择（内容: CodeIgniter72）
│   ├── config/
│   │   └── system.php        # 系统配置 (SYS_HTTPS=1, SYS_301=0)
│   ├── data/                   # 站点数据缓存（关键！不能随意删除）
│   ├── template/              # 模板编译缓存
│   ├── file/
│   ├── session/
│   └── log/
├── config/
│   └── database.php          # 数据库配置
├── dayrui/                    # CMS核心
│   ├── App/                   # 应用
│   ├── CodeIgniter72/         # CI框架
│   ├── Fcms/                  # CMS核心
│   └── My/                    # 自定义
├── index.php                  # 入口文件
├── mobile/                    # 移动端入口
├── static/                    # 静态资源
├── template/                  # 模板目录
│   ├── pc/default/           # PC模板
│   └── mobile/default/      # 移动模板
└── uploadfile/                # 上传目录 (11M)
```

### ⚠️ 缓存目录关键约定

**绝对不能执行 `rm -rf cache/*`！** 这会删除以下关键文件:

| 文件 | 作用 | 删除后果 |
|------|------|----------|
| install.lock | 标记CMS已安装 | 重定向到install.php |
| frame.lock | 框架选择 | 500错误（找不到System/Init.php） |
| config/system.php | 系统配置 | HTTPS→HTTP 301死循环 |
| data/ 目录 | 站点数据缓存 | 所有动态内容消失 |

**正确清缓存方式**:
```bash
# 只删除模板编译缓存和数据缓存
rm -rf cache/template/*
rm -rf cache/data/*
# 但保留 install.lock, frame.lock, config/system.php
```

### 模板结构

| 模板集 | 路径 | 说明 |
|--------|------|------|
| PC | template/pc/default/ | 首页、分类、详情页 |
| Mobile | template/mobile/default/ | 移动版首页、分类、详情页 |

PC模板目录: `config.ini, dev, home, member, thumb.jpg`  
Mobile模板目录: `config.ini, home, member, thumb.jpg`

---

## 六、日志

| 日志 | 路径 | 说明 |
|------|------|------|
| Nginx access | /var/log/nginx/access.log | 正常 |
| Nginx error | /var/log/nginx/error.log | 有扫描攻击记录 |
| PHP | /www/wwwroot/59.110.217.6/log/ | 空目录 |
| CMS | /www/wwwroot/59.110.217.6/cache/log/ | CMS运行日志 |

### 近期错误日志

Nginx error.log 显示有外部扫描 `.env` 和 `.git/HEAD` 的攻击尝试，已被Nginx deny规则拦截。

---

## 七、systemd 服务

| 服务 | 状态 |
|------|------|
| nginx | enabled, active |
| php7.4-fpm | enabled, active |
| mariadb | enabled, active |
| certbot.timer | enabled, active (waiting) |

---

## 八、上传目录

| 项目 | 值 |
|------|-----|
| 路径 | /www/wwwroot/59.110.217.6/uploadfile/ |
| 大小 | 11M |
| 子目录 | 202601, 202602, 202605, 202606, 202607, 202608, member, thumb, weixin |
| Git排除 | 是 (.gitignore中 site/uploadfile/) |
| Nginx保护 | .php在uploadfile下被deny |

---

## 九、HTTPS 最终状态

| 项目 | 值 |
|------|-----|
| 主域名 | https://www.laocaimi.org |
| HTTP→HTTPS | ✅ 301重定向 |
| non-www→www | ✅ 重定向 |
| 证书提供商 | Let's Encrypt |
| 证书路径 | /etc/letsencrypt/live/laocaimi.org/ |
| 证书到期 | 2026-11-08 02:27:37 UTC |
| Certbot | 已安装 |
| 自动续期 | ✅ certbot.timer active |
| HSTS | ✅ max-age=31536000 |
| Mixed Content | 未检测到（需进一步验证） |

**验证方式**: `curl -sk https://www.laocaimi.org/` 返回200 OK，62,982字节。

---

## 十、Cron 与定时任务

| 项目 | 状态 |
|------|------|
| root crontab | 空（no crontab for root） |
| /etc/cron.d/ | 无自定义任务 |
| systemd timers | certbot.timer, phpsessionclean.timer, apt-daily等系统默认 |
| CMS内部计划任务 | 未发现 |

**当前无自定义定时任务。** 文章自动发布系统需要新建cron或systemd timer。

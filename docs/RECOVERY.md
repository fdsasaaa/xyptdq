# 灾难恢复说明 (RECOVERY)

> 本文件不含真实密码或私钥。

## 恢复层次

### 第一层：GitHub 版本恢复
通过Git回退到任意历史版本。

### 第二层：系统数据恢复
通过独立备份恢复数据库、上传文件、配置。

---

## A. 恢复网站文件

### 从GitHub
```bash
# 克隆仓库
git clone https://github.com/fdsasaaa/xyptdq.git
cd xyptdq

# 切换到目标版本
git checkout <tag-or-commit>

# 同步到服务器
rsync -avz --exclude='.git' --exclude='cache' --exclude='uploadfile' \
    site/ root@94.103.5.248:/www/wwwroot/59.110.217.6/
```

### 从服务器备份
```bash
# 服务器上的备份位于:
# /root/backups/disaster_recovery_20260810_031958/

# 恢复网站文件
cd /www/wwwroot/59.110.217.6
tar xzf /root/backups/disaster_recovery_20260810_031958/website_files_www_59.110.217.6.tar.gz
```

## B. 恢复数据库

```bash
# 恢复 dayrui 数据库
mysql dayrui < /root/backups/disaster_recovery_20260810_031958/database_dayrui.sql

# 恢复全部数据库
mysql < /root/backups/disaster_recovery_20260810_031958/database_all.sql
```

数据库凭据存放于:
`/www/wwwroot/59.110.217.6/config/database.php`

## C. 恢复Web服务器配置

```bash
# 恢复Nginx配置
cd /
tar xzf /root/backups/disaster_recovery_20260810_031958/nginx_configs.tar.gz

# 测试配置
nginx -t

# 重载
systemctl reload nginx
```

## D. 恢复SSL证书

```bash
# Let's Encrypt 证书位于:
# /etc/letsencrypt/live/laocaimi.org/

# 如果证书丢失，重新申请:
certbot certonly --nginx -d laocaimi.org -d www.laocaimi.org --non-interactive --agree-tos
```

## E. 恢复系统服务

```bash
# 恢复PHP-FPM配置
cp /root/backups/disaster_recovery_20260810_031958/php_fpm_www.conf /etc/php/7.4/fpm/pool.d/www.conf
systemctl restart php7.4-fpm

# 恢复MariaDB配置
cp /root/backups/disaster_recovery_20260810_031958/mariadb_server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mariadb
```

## F. 恢复GitHub版本

```bash
# 查看所有Tag
git tag -l

# 回退到基线
git checkout production-baseline-v1

# 强制推送回退（谨慎！）
# git push --force origin production-baseline-v1:main
```

## 验证清单

恢复完成后必须验证：

- [ ] Nginx启动正常 (`nginx -t`)
- [ ] PHP-FPM运行 (`systemctl status php7.4-fpm`)
- [ ] MariaDB运行 (`systemctl status mariadb`)
- [ ] 网站首页可访问 (`curl -I https://www.laocaimi.org`)
- [ ] HTTPS证书有效 (`openssl s_client`)
- [ ] HTTP→HTTPS重定向正常
- [ ] 数据库连接正常

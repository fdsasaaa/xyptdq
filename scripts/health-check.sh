#!/bin/bash
# ============================================================
# health-check.sh - 网站健康检查
# 使用: ./health-check.sh
# ============================================================
echo "=== 网站健康检查 ==="
echo "时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

PASS=0
FAIL=0

check() {
    local name="$1"
    local result="$2"
    if [ "$result" = "OK" ]; then
        echo "[✅] $name"
        PASS=$((PASS + 1))
    else
        echo "[❌] $name: $result"
        FAIL=$((FAIL + 1))
    fi
}

# 1. Nginx
NGINX_STATUS=$(systemctl is-active nginx 2>/dev/null)
check "Nginx服务" "$NGINX_STATUS" "active"

# 2. PHP-FPM
PHPFPM_STATUS=$(systemctl is-active php7.4-fpm 2>/dev/null)
check "PHP-FPM服务" "$PHPFPM_STATUS" "active"

# 3. MariaDB
MYSQL_STATUS=$(systemctl is-active mariadb 2>/dev/null)
check "MariaDB服务" "$MYSQL_STATUS" "active"

# 4. HTTPS首页
HTTP_CODE=$(curl -sk -o /dev/null -w '%{http_code}' https://www.laocaimi.org 2>/dev/null)
if [ "$HTTP_CODE" = "200" ]; then
    check "HTTPS首页" "OK"
else
    check "HTTPS首页" "HTTP $HTTP_CODE"
fi

# 5. HTTP重定向
REDIRECT=$(curl -sk -o /dev/null -w '%{http_code}' http://www.laocaimi.org 2>/dev/null)
if [ "$REDIRECT" = "301" ]; then
    check "HTTP→HTTPS重定向" "OK"
else
    check "HTTP→HTTPS重定向" "HTTP $REDIRECT"
fi

# 6. SSL证书有效期
CERT_DAYS=$(echo | openssl s_client -connect 127.0.0.1:443 -servername www.laocaimi.org 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 | xargs -I{} date -d "{}" +%s 2>/dev/null)
NOW=$(date +%s)
DAYS_LEFT=$(( (CERT_DAYS - NOW) / 86400 2>/dev/null || echo 0 ))
if [ "$DAYS_LEFT" -gt 7 ]; then
    check "SSL证书 (${DAYS_LEFT}天剩余)" "OK"
else
    check "SSL证书 (${DAYS_LEFT}天剩余)" "WARNING"
fi

# 7. 磁盘空间
DISK_PCT=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [ "$DISK_PCT" -lt 90 ]; then
    check "磁盘空间 (${DISK_PCT}%使用)" "OK"
else
    check "磁盘空间 (${DISK_PCT}%使用)" "WARNING"
fi

# 8. 数据库连接
DB_CHECK=$(mysql -e "SELECT 1;" 2>/dev/null && echo "OK" || echo "FAIL")
check "数据库连接" "$DB_CHECK"

# 9. Nginx配置测试
NGINX_TEST=$(nginx -t 2>&1 | grep -c "successful")
if [ "$NGINX_TEST" -gt 0 ]; then
    check "Nginx配置" "OK"
else
    check "Nginx配置" "FAIL"
fi

echo ""
echo "=== 结果: $PASS 通过, $FAIL 失败 ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

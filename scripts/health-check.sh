#!/bin/bash
# ============================================================
# health-check.sh - 生产网站基础健康检查
# ============================================================
set -u

PASS=0
FAIL=0

ok() {
    echo "[OK] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1${2:+: $2}"
    FAIL=$((FAIL + 1))
}

check_service() {
    local label="$1"
    local unit="$2"
    local state
    state=$(systemctl is-active "$unit" 2>/dev/null || true)
    if [ "$state" = "active" ]; then
        ok "$label"
    else
        fail "$label" "state=${state:-unknown}"
    fi
}

echo "=== 网站健康检查 ==="
echo "时间: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo

check_service "Nginx服务" nginx
check_service "PHP-FPM服务" php7.4-fpm
check_service "MariaDB服务" mariadb

HTTP_CODE=$(curl -sS -k -o /dev/null -w '%{http_code}' --max-time 15 https://www.laocaimi.org/ 2>/dev/null || true)
if [ "$HTTP_CODE" = "200" ]; then
    ok "HTTPS首页"
else
    fail "HTTPS首页" "HTTP ${HTTP_CODE:-no-response}"
fi

HTTP_REDIRECT=$(curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 15 http://www.laocaimi.org/ 2>/dev/null || true)
case "$HTTP_REDIRECT" in
    301\ https://www.laocaimi.org/*|302\ https://www.laocaimi.org/*|308\ https://www.laocaimi.org/*)
        ok "HTTP→HTTPS重定向"
        ;;
    *)
        fail "HTTP→HTTPS重定向" "${HTTP_REDIRECT:-no-response}"
        ;;
esac

CERT_END=$(echo | openssl s_client -connect 127.0.0.1:443 -servername www.laocaimi.org 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2- || true)
if [ -n "$CERT_END" ]; then
    CERT_TS=$(date -d "$CERT_END" +%s 2>/dev/null || echo 0)
    NOW_TS=$(date +%s)
    if [ "$CERT_TS" -gt 0 ] 2>/dev/null; then
        DAYS_LEFT=$(( (CERT_TS - NOW_TS) / 86400 ))
        if [ "$DAYS_LEFT" -gt 14 ]; then
            ok "SSL证书 (${DAYS_LEFT}天剩余)"
        else
            fail "SSL证书" "仅剩${DAYS_LEFT}天"
        fi
    else
        fail "SSL证书" "无法解析到期时间"
    fi
else
    fail "SSL证书" "无法读取证书"
fi

DISK_PCT=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
if [ -n "$DISK_PCT" ] && [ "$DISK_PCT" -lt 90 ] 2>/dev/null; then
    ok "磁盘空间 (${DISK_PCT}%使用)"
else
    fail "磁盘空间" "${DISK_PCT:-unknown}%使用"
fi

if mysql -Nse 'SELECT 1' >/dev/null 2>&1; then
    ok "数据库连接"
else
    fail "数据库连接" "mysql local socket test failed"
fi

if nginx -t >/tmp/xyptdq_nginx_test.log 2>&1; then
    ok "Nginx配置语法"
else
    fail "Nginx配置语法" "$(tail -n 2 /tmp/xyptdq_nginx_test.log | tr '\n' ' ')"
fi
rm -f /tmp/xyptdq_nginx_test.log

echo
echo "=== 结果: $PASS 通过, $FAIL 失败 ==="
[ "$FAIL" -eq 0 ]

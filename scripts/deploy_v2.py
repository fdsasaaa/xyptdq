#!/usr/bin/env python3
"""Deploy updated templates with PHP direct query approach and test"""

import paramiko
import time

SSH_HOST = '94.103.5.248'
SSH_PORT = 22
SSH_USER = 'root'
SSH_PASS = 'EOSD6OKvnhd8'

PC_TEMPLATE = 'G:/我的云端硬盘/BC/信誉平台大全网站/site/template/pc/default/home/index.html'
MOBILE_TEMPLATE = 'G:/我的云端硬盘/BC/信誉平台大全网站/site/template/mobile/default/home/index.html'

REMOTE_PC = '/www/wwwroot/59.110.217.6/template/pc/default/home/index.html'
REMOTE_MOBILE = '/www/wwwroot/59.110.217.6/template/mobile/default/home/index.html'

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(SSH_HOST, port=SSH_PORT, username=SSH_USER, password=SSH_PASS, timeout=30)

def run_cmd(cmd, desc=""):
    if desc:
        print(f"\n=== {desc} ===")
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='replace')
    err = stderr.read().decode('utf-8', errors='replace')
    if out:
        print(out)
    if err:
        print(f"STDERR: {err}")
    return out, err

# Step 1: Upload templates
print("=" * 60)
print("Step 1: Upload updated templates")
print("=" * 60)
sftp = ssh.open_sftp()
print("Uploading PC template...")
sftp.put(PC_TEMPLATE, REMOTE_PC)
print("Uploading Mobile template...")
sftp.put(MOBILE_TEMPLATE, REMOTE_MOBILE)
sftp.close()

run_cmd(f'chown www-data:www-data {REMOTE_PC} {REMOTE_MOBILE}')
run_cmd(f'chmod 644 {REMOTE_PC} {REMOTE_MOBILE}')

# Step 2: Clear ALL cache
print("\n" + "=" * 60)
print("Step 2: Clear ALL cache")
print("=" * 60)
run_cmd('rm -rf /www/wwwroot/59.110.217.6/cache/*')
run_cmd('mkdir -p /www/wwwroot/59.110.217.6/cache/{data,template,file,attachment,config,log,session,temp}')
run_cmd('echo -n "CodeIgniter72" > /www/wwwroot/59.110.217.6/cache/frame.lock')
run_cmd('echo "2026-02-03 04:14:00" > /www/wwwroot/59.110.217.6/cache/install.lock')
run_cmd("""cat > /www/wwwroot/59.110.217.6/cache/config/system.php << 'PHPEOF'
<?php
return [
    'SYS_HTTPS' => 1,
    'SYS_301' => 0,
];
PHPEOF""")
run_cmd('chown -R www-data:www-data /www/wwwroot/59.110.217.6/cache/')
run_cmd('chmod -R 777 /www/wwwroot/59.110.217.6/cache/')

# Restart PHP-FPM to clear opcache
run_cmd('systemctl restart php7.4-fpm')
time.sleep(3)

# Step 3: Test
print("\n" + "=" * 60)
print("Step 3: Test")
print("=" * 60)

run_cmd(
    'curl -s -k -o /dev/null -w "HTTP Code: %{http_code}\\nSize: %{size_download}\\n" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/',
    "PC HTTP status"
)

run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | grep -o "信誉平台选择[^<]*\\|2026年最新[^<]*\\|平台安全防护[^<]*"',
    "PC: Article titles found"
)

run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | sed -n "/seo-article-list/,/<\\/ul>/p"',
    "PC: Article list HTML"
)

# Check for errors
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | grep -i "fatal\\|error\\|warning\\|不可写" | head -5',
    "PC: Error check"
)

# Mobile test
run_cmd(
    'curl -s -k -o /dev/null -w "HTTP Code: %{http_code}\\nSize: %{size_download}\\n" -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" https://www.laocaimi.org/',
    "Mobile HTTP status"
)

run_cmd(
    'curl -s -k -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" https://www.laocaimi.org/ | grep -o "信誉平台选择[^<]*\\|2026年最新[^<]*\\|平台安全防护[^<]*"',
    "Mobile: Article titles found"
)

# Full article list section check
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | wc -c',
    "PC total page size"
)

ssh.close()
print("\n" + "=" * 60)
print("Done!")
print("=" * 60)

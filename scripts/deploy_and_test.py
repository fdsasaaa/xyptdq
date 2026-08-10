#!/usr/bin/env python3
"""Deploy modified templates to production server and test"""

import paramiko
import time

SSH_HOST = '94.103.5.248'
SSH_PORT = 22
SSH_USER = 'root'
SSH_PASS = 'EOSD6OKvnhd8'

# Local template paths
PC_TEMPLATE = 'G:/我的云端硬盘/BC/信誉平台大全网站/site/template/pc/default/home/index.html'
MOBILE_TEMPLATE = 'G:/我的云端硬盘/BC/信誉平台大全网站/site/template/mobile/default/home/index.html'

# Remote paths
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

# Step 1: Backup current templates on server
print("=" * 60)
print("Step 1: Backup current production templates")
print("=" * 60)
timestamp = time.strftime('%Y%m%d_%H%M%S')
run_cmd(f'mkdir -p /root/xyptdq/backups/templates_{timestamp}')
run_cmd(f'cp {REMOTE_PC} /root/xyptdq/backups/templates_{timestamp}/pc_index.html.bak')
run_cmd(f'cp {REMOTE_MOBILE} /root/xyptdq/backups/templates_{timestamp}/mobile_index.html.bak')
run_cmd(f'ls -la /root/xyptdq/backups/templates_{timestamp}/', "Backup verification")

# Step 2: Upload new templates via SFTP
print("\n" + "=" * 60)
print("Step 2: Upload new templates via SFTP")
print("=" * 60)
sftp = ssh.open_sftp()

print(f"Uploading PC template...")
sftp.put(PC_TEMPLATE, REMOTE_PC)
print(f"  -> {REMOTE_PC} OK")

print(f"Uploading Mobile template...")
sftp.put(MOBILE_TEMPLATE, REMOTE_MOBILE)
print(f"  -> {REMOTE_MOBILE} OK")

sftp.close()

# Step 3: Fix permissions
print("\n" + "=" * 60)
print("Step 3: Fix permissions")
print("=" * 60)
run_cmd(f'chown www-data:www-data {REMOTE_PC} {REMOTE_MOBILE}')
run_cmd(f'chmod 644 {REMOTE_PC} {REMOTE_MOBILE}')
run_cmd(f'ls -la {REMOTE_PC} {REMOTE_MOBILE}', "Permission verify")

# Step 4: Clear CMS cache
print("\n" + "=" * 60)
print("Step 4: Clear CMS cache")
print("=" * 60)
run_cmd('rm -rf /www/wwwroot/59.110.217.6/cache/*')
run_cmd('ls -la /www/wwwroot/59.110.217.6/cache/', "Cache dir after clear")

# Step 5: Test production - HTTP status and content
print("\n" + "=" * 60)
print("Step 5: Test production")
print("=" * 60)

# Test PC (using curl with desktop user agent)
run_cmd(
    'curl -s -o /dev/null -w "%{http_code}" -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/',
    "PC HTTP status code"
)

# Check if SEO article section appears in the page HTML
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | grep -c "seo-article-section"',
    "PC: SEO article section found?"
)

# Test mobile (using mobile user agent)
run_cmd(
    'curl -s -o /dev/null -w "%{http_code}" -k -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" https://www.laocaimi.org/',
    "Mobile HTTP status code"
)

# Check if mobile has the new section
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" https://www.laocaimi.org/ | grep -c "最新文章"',
    "Mobile: SEO article section found?"
)

# Also check for PHP errors in the page
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | grep -i "error\\|warning\\|fatal\\|notice" | head -5',
    "PC: PHP errors check"
)

# Check nginx error log
run_cmd('tail -5 /var/log/nginx/error.log', "Nginx error log (last 5 lines)")

# Step 6: Verify template syntax (check if CMS can render without errors)
print("\n" + "=" * 60)
print("Step 6: Full page content check")
print("=" * 60)
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | wc -c',
    "PC page size (bytes)"
)
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" https://www.laocaimi.org/ | wc -c',
    "Mobile page size (bytes)"
)

# Check if the article list is rendering (even if empty, the section HTML should be there)
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | grep -o "seo-article-section" | head -1',
    "PC: seo-article-section marker"
)
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)" https://www.laocaimi.org/ | grep -o "最新文章" | head -1',
    "Mobile: 最新文章 marker"
)

ssh.close()
print("\n" + "=" * 60)
print("Deployment and test complete!")
print("=" * 60)

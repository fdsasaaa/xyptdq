#!/usr/bin/env python3
"""Create test SEO articles to verify the article list on homepage"""

import paramiko

SSH_HOST = '94.103.5.248'
SSH_PORT = 22
SSH_USER = 'root'
SSH_PASS = 'EOSD6OKvnhd8'

DB_USER = 'dayruiuser'
DB_PASS = 'kcJMfaLlqCEVPt4LKmdCncQ669R79Fen'
DB_NAME = 'dayrui'

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

# Create 3 test articles in catid=7 (SEO文章)
# Use a SQL file to avoid escaping issues
articles_sql = """
-- Article 1
INSERT INTO dr_1_news (catid, title, thumb, keywords, description, hits, uid, author, status, url, link_id, tableid, inputip, inputtime, updatetime, displayorder)
VALUES (7, '信誉平台选择指南：如何识别可靠的平台', '', '信誉平台,平台选择,安全可靠', '本文详细介绍如何从多个维度识别和选择信誉良好的平台，确保您的资金安全。', 0, 1, 'admin', 9, '', 0, 0, '127.0.0.1-0', UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), 0);
SET @aid1 = LAST_INSERT_ID();
UPDATE dr_1_news SET url=CONCAT('/index.php?c=show&id=', @aid1) WHERE id=@aid1;
INSERT INTO dr_1_news_data_0 (id, uid, catid, content) VALUES (@aid1, 1, 7, '<p>信誉平台选择指南正文内容...</p>');
INSERT INTO dr_1_news_index (id, uid, catid, status, inputtime) VALUES (@aid1, 1, 7, 9, UNIX_TIMESTAMP());

-- Article 2
INSERT INTO dr_1_news (catid, title, thumb, keywords, description, hits, uid, author, status, url, link_id, tableid, inputip, inputtime, updatetime, displayorder)
VALUES (7, '2026年最新信誉平台排行榜与评测', '', '信誉平台排行,平台评测,2026排行', '全面评测各大信誉平台，从安全性、稳定性、用户体验等多角度进行排名。', 0, 1, 'admin', 9, '', 0, 0, '127.0.0.1-0', UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), 0);
SET @aid2 = LAST_INSERT_ID();
UPDATE dr_1_news SET url=CONCAT('/index.php?c=show&id=', @aid2) WHERE id=@aid2;
INSERT INTO dr_1_news_data_0 (id, uid, catid, content) VALUES (@aid2, 1, 7, '<p>2026年信誉平台排行榜正文内容...</p>');
INSERT INTO dr_1_news_index (id, uid, catid, status, inputtime) VALUES (@aid2, 1, 7, 9, UNIX_TIMESTAMP());

-- Article 3
INSERT INTO dr_1_news (catid, title, thumb, keywords, description, hits, uid, author, status, url, link_id, tableid, inputip, inputtime, updatetime, displayorder)
VALUES (7, '平台安全防护措施详解：从注册到使用', '', '平台安全,安全防护,注册安全', '详细介绍平台使用过程中的安全防护措施，包括账户安全、资金安全等方面。', 0, 1, 'admin', 9, '', 0, 0, '127.0.0.1-0', UNIX_TIMESTAMP(), UNIX_TIMESTAMP(), 0);
SET @aid3 = LAST_INSERT_ID();
UPDATE dr_1_news SET url=CONCAT('/index.php?c=show&id=', @aid3) WHERE id=@aid3;
INSERT INTO dr_1_news_data_0 (id, uid, catid, content) VALUES (@aid3, 1, 7, '<p>平台安全防护措施详解正文内容...</p>');
INSERT INTO dr_1_news_index (id, uid, catid, status, inputtime) VALUES (@aid3, 1, 7, 9, UNIX_TIMESTAMP());
"""

# Write SQL to temp file
run_cmd(f"""cat > /tmp/create_test_articles.sql << 'SQLEOF'
{articles_sql}
SQLEOF""", "Write test articles SQL")

# Execute
run_cmd(f'mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} < /tmp/create_test_articles.sql', "Execute article creation")

# Verify
run_cmd(
    f'mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} -e "SELECT id,catid,title,status,url FROM dr_1_news WHERE catid=7 ORDER BY id;"',
    "SEO articles created"
)

# Clean up
run_cmd('rm /tmp/create_test_articles.sql')

# Clear cache
run_cmd('rm -rf /www/wwwroot/59.110.217.6/cache/template/* /www/wwwroot/59.110.217.6/cache/data/*')
run_cmd('chown -R www-data:www-data /www/wwwroot/59.110.217.6/cache/')
run_cmd('chmod -R 777 /www/wwwroot/59.110.217.6/cache/')

# Test homepage: should now show the articles
print("\n" + "=" * 60)
print("HOMEPAGE TEST WITH ARTICLES")
print("=" * 60)

run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | grep -c "seo-article"',
    "SEO article markers count"
)

# Get the article list items
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | grep -o "信誉平台[^<]*\\|2026年[^<]*\\|平台安全[^<]*"',
    "Article titles found on homepage"
)

# Get the full article list HTML
run_cmd(
    'curl -s -k -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/ | sed -n "/seo-article-list/,/<\\/ul>/p"',
    "Full article list HTML"
)

# Check page loads OK
run_cmd(
    'curl -s -k -o /dev/null -w "HTTP Code: %{http_code}\\nSize: %{size_download}\\n" -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" https://www.laocaimi.org/',
    "Page status"
)

ssh.close()

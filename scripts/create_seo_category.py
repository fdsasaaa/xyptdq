#!/usr/bin/env python3
"""Create SEO article category in Xunrui CMS database via SSH"""

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

# Step 1: Check current categories
run_cmd(
    f'mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} -e "SELECT id,pid,mid,name,dirname FROM dr_1_share_category ORDER BY id;"',
    "Step 1: Current categories"
)

# Step 2: Insert new category using a temp SQL file
# Using the exact same structure as existing categories
sql_content = """INSERT INTO dr_1_share_category (tid, pid, mid, pids, name, dirname, pdirname, child, disabled, ismain, childids, thumb, `show`, content, setting, displayorder)
VALUES (1, 0, 'news', '0', 'SEO文章', 'seo-articles', '', 0, 0, 1, '', '', 1, '', '{"disabled":"0","linkurl":"","getchild":"0","notedit":"0","urlrule":"0","seo":{"list_title":"[第{page}页{join}]{name}{join}{SITE_NAME}","list_keywords":"","list_description":""},"template":{"pagesize":"20","mpagesize":"20","page":"","list":"list.html","category":"category.html","search":"search.html","show":"article.html"},"cat_field":null,"module_field":null}', 0);"""

run_cmd(f"cat > /tmp/insert_seo_category.sql << 'SQLEOF'\n{sql_content}\nSQLEOF", "Step 2: Write SQL file")

run_cmd(f'mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} < /tmp/insert_seo_category.sql', "Step 3: Execute INSERT")

# Step 4: Verify and get new ID
run_cmd(
    f"""mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} -e "SELECT id,pid,mid,name,dirname FROM dr_1_share_category WHERE dirname='seo-articles';" """,
    "Step 4: Verify new category"
)

# Show all categories
run_cmd(
    f'mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} -e "SELECT id,pid,mid,name,dirname FROM dr_1_share_category ORDER BY id;"',
    "Step 5: All categories after insert"
)

# Also need to update the childids field for the new category (should be its own id)
# First get the new id
stdin, stdout, stderr = ssh.exec_command(
    f"""mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} -N -e "SELECT id FROM dr_1_share_category WHERE dirname='seo-articles';" """
)
new_id = stdout.read().decode('utf-8', errors='replace').strip()
print(f"\nNew category ID: {new_id}")

if new_id:
    # Update childids to be its own id (Xunrui CMS convention)
    run_cmd(
        f'mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} -e "UPDATE dr_1_share_category SET childids=\'{new_id}\' WHERE id={new_id};"'
    )

# Clean up
run_cmd("rm -f /tmp/insert_seo_category.sql")

# Clear CMS cache
run_cmd("rm -rf /www/wwwroot/59.110.217.6/cache/*", "Step 6: Clear CMS cache")

# Final verification
run_cmd(
    f'mysql -u{DB_USER} -p{DB_PASS} {DB_NAME} -e "SELECT id,pid,mid,name,dirname,childids FROM dr_1_share_category ORDER BY id;"',
    "Final: All categories"
)

ssh.close()
print("\nDone.")

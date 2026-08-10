# CMS database credential rotation

The application database credential must be treated as exposed because a production `site/config/database.php` was previously tracked in Git history. Deleting the file from current `main` is necessary but does not invalidate the old credential.

## Tool

`scripts/security/rotate_cms_db_password.sh`

The script is designed for the current MariaDB 10.3 / Xunrui CMS production host. It never prints password values. It stages the old password only in a root-only temporary directory so it can automatically roll back if the new credential fails database or HTTP verification.

## Required sequence

1. Create a fresh full backup.
2. Update the server Git working copy to the reviewed `main`.
3. Run preflight:

```bash
cd /opt/xyptdq-repo
./scripts/security/rotate_cms_db_password.sh
```

Expected: `PRECHECK PASS` followed by `DRY-RUN ONLY`.

4. Apply:

```bash
./scripts/security/rotate_cms_db_password.sh --apply
```

Expected: `ROTATED AND VERIFIED` plus HTTP status codes only.

## Stop conditions

Do not bypass any of these failures:

- configured CMS credentials do not connect before rotation;
- the configured hostname does not map to an exact MariaDB user/Host account;
- the app account uses an unexpected authentication plugin;
- local administrative socket authentication is unavailable;
- the CMS config password field cannot be replaced exactly once;
- homepage or known article stops returning HTTP 200.

## Other credentials

This script rotates only the CMS database application password. The previously shared SSH root password and CMS administrator credential are separate security items. They should also be rotated, but only after a safe alternative administrator login method is confirmed. Do not disable SSH password login until a tested key-based administrator path exists.

# Troubleshooting Guide

Common errors encountered during ERPNext installation on Ubuntu 22.04/24.04 and their solutions.

---

## 1. python3-distutils not found

**Error:**
```
Package python3-distutils is not available, but is referred to by another package.
E: Package 'python3-distutils' has no installation candidate
```

**Cause:** Ubuntu 24.04 removed `python3-distutils`. It's not needed for Python 3.11+.

**Solution:** Remove `python3-distutils` from the apt install list. The `setuptools` package handles the same functionality. Fixed in script v2.0.1.

---

## 2. MariaDB 10.6 not available on Ubuntu 24.04

**Error:**
```
[error] MariaDB Server version 10.6 is not working.
         The latest MariaDB Server versions are:
             10.6.27 10.11.18 11.4.12 11.8.8 12.3.2
```

**Cause:** MariaDB 10.6 is EOL for Ubuntu 24.04 (Noble). Minimum supported is 10.11.

**Solution:** Script auto-detects OS and falls back:
- Ubuntu 22.04 → MariaDB 10.6
- Ubuntu 24.04 → MariaDB 10.11 (system default)
- If repo setup fails → falls back to system default

Fixed in v2.0.2.

---

## 3. Host '127.0.0.1' not allowed to connect

**Error:**
```
pymysql.err.OperationalError: (1130, "Host '127.0.0.1' is not allowed to connect to this MariaDB server")
```

**Cause:** Frappe bench connects to MariaDB via TCP on `127.0.0.1`, but only `root@localhost` (Unix socket) was configured.

**Solution:** Create `root@127.0.0.1` alongside `root@localhost`:
```sql
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('your_password');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```
Fixed in script v2.0.3.

---

## 4. Redis connection refused during app install

**Error:**
```
redis.exceptions.ConnectionError: Error 111 connecting to 127.0.0.1:11000. Connection refused.
Please make sure that Redis Queue runs @ redis://127.0.0.1:11000.
```

**Cause:** `bench install-app erpnext` requires bench Redis services (port 11000 for queue, 13000 for cache). These only run when `bench start` is active.

**Solution:**
```bash
cd ~/frappe-bench
bench start &>/tmp/bench-start.log &
sleep 15
bench --site mysite install-app erpnext
# cleanup:
kill %1
```

Fixed in script v2.0.4 — bench services are started automatically before app install and stopped after.

---

## 5. Site returns 404 on first access

**Error:**
```
192.168.x.x - - [DATE] "GET / HTTP/1.1" 404 -
```

**Cause:** No default site is configured. Frappe routes requests by Host header and falls back to `currentsite.txt`.

**Solution:**
```bash
cd ~/frappe-bench
bench use mysite.local
```
Or manually:
```bash
echo "mysite.local" > sites/currentsite.txt
```
Fixed in script v2.0.5.

---

## 6. Access denied for root@localhost (using password: NO)

**Error:**
```
ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: NO)
```

**Cause:** After the script sets the root password via `mysql_native_password`, `sudo mysql` without `-p` no longer works. The root user is now password-protected.

**Solution:**
```bash
sudo mysql -p
# Enter the password from ~/frappe_passwords.txt
```

---

## 7. bench command not found

**Error:**
```
Command 'bench' not found, did you mean...
```

**Cause:** `~/.local/bin` is not in the current shell's PATH. The script adds it to `~/.bashrc` but the current session doesn't have it.

**Solution:**
```bash
export PATH="$HOME/.local/bin:$PATH"
source ~/.profile
# To make permanent:
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

---

## 8. wkhtmltopdf not found / installation failed

**Error:**
```
[WARN] wkhtmltopdf installation may have failed
```

**Cause:** GitHub release file not found for the current Ubuntu version, or download failed.

**Solution:** Install via apt as fallback:
```bash
sudo apt install -y wkhtmltopdf
```
Or install manually:
```bash
wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo dpkg -i wkhtmltox_0.12.6.1-2.jammy_amd64.deb
sudo apt --fix-broken install -y
```

---

## 9. Low RAM / disk space warnings

```
[WARN] RAM is less than 4GB
[WARN] Disk space is less than 40GB
```

**Cause:** ERPNext requires significant resources for production use.

**Solution:**
- **RAM:** The script auto-creates a 4GB swap file if RAM < 8GB. For virtual machines, allocate more RAM.
- **Disk:** 40GB minimum recommended. Expand disk or free space. Database + assets grow over time.

---

## 10. MariaDB version warning

```
Warning: MariaDB version ['10.11', '14'] is more than 10.8 which is not yet tested with Frappe Framework.
```

**Cause:** Frappe Framework v15 was tested up to MariaDB 10.8. MariaDB 10.11 (Ubuntu 24.04 default) works but shows this warning.

**Impact:** None. This is a cosmetic warning. MariaDB 10.11 has been tested extensively by the community with Frappe v15 and works fine.

---

## 11. Wkhtmltopdf deprecation warning

```
QStandardPaths: XDG_RUNTIME_DIR not set, defaulting to '/tmp/...'
```

**Cause:** wkhtmltopdf 0.12.6.1 relies on deprecated Qt libraries.

**Solution:** Ignore — this does not affect PDF generation. Future Frappe versions will migrate away from wkhtmltopdf.

---

## 12. Nginx "unknown log format main" error

**Error:**
```
nginx: [emerg] unknown log format "main" in /etc/nginx/conf.d/frappe-bench.conf
```

**Cause:** Missing `mime.types` include in nginx.conf.

**Solution:**
```bash
sudo sed -i '/http {/a\    include /etc/nginx/mime.types;' /etc/nginx/nginx.conf
sudo nginx -t
sudo service nginx restart
```

---

## 13. caniuse-lite outdated warning

```
Browserslist: caniuse-lite is outdated. Please run:
  npx update-browserslist-db@latest
```

**Cause:** Browser compatibility database bundled with Frappe is stale.

**Solution (optional):**
```bash
cd ~/frappe-bench
npx update-browserslist-db@latest
```

---

## Quick Reference: Manual Recovery Steps

If the script partially completes, use these manual steps to recover:

```bash
# 1. Set PATH
export PATH="$HOME/.local/bin:$PATH"

# 2. Fix MariaDB root access
sudo mysql -p <<SQL
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED VIA mysql_native_password USING PASSWORD('your_db_password');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

# 3. Drop failed site
cd ~/frappe-bench
bench drop-site mysite --no-backup --db-root-password your_db_password

# 4. Create new site
bench new-site mysite --db-password your_db_password

# 5. Start bench services
bench start &
sleep 15

# 6. Install apps
bench --site mysite install-app erpnext
bench --site mysite install-app payments

# 7. Set as default + enable scheduler
bench use mysite
bench --site mysite enable-scheduler

# 8. Stop background bench
kill %1

# 9. Start fresh
bench start
```

---

## Version History

| Version | Fixes |
|---------|-------|
| v2.0.1 | python3-distutils on Ubuntu 24.04 |
| v2.0.2 | MariaDB OS-aware version + wkhtmltopdf fallback |
| v2.0.3 | root@127.0.0.1 TCP access |
| v2.0.4 | Bench services before install-app + mysql re-run auth |
| v2.0.5 | Default site with bench use |

*Last updated: Aug 2026 — Ubuntu 24.04 + ERPNext v15 live test*

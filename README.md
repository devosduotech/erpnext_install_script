# ERPNext Installation Script

Automated bare-metal installation script for ERPNext on Ubuntu VPS and dedicated servers. Supports both interactive and one-liner non-interactive modes.

## Supported Versions

| ERPNext | Python | Node.js | MariaDB | Ubuntu |
|---------|--------|---------|---------|--------|
| **v14** (Legacy) | 3.10 | 18 | 10.6 | 22.04, 24.04 |
| **v15** (Stable) | 3.11 | 18 | 10.6 | 22.04, 24.04 |
| **v16** (Latest) | 3.12 | 20 | 11.3 | 22.04, 24.04 |

---

## One-Liner Install

From a fresh Ubuntu machine with a non-root sudo user:

```bash
wget -qO- https://raw.githubusercontent.com/devosduotech/erpnext_install_script/main/install_frappe.sh | bash -s -- --site erp.example.com
```

### Examples

**Minimal (v15, development, ERPNext only):**
```bash
bash install_frappe.sh --site erp.example.com
```

**Production with HRMS and SSL:**
```bash
bash install_frappe.sh --site erp.example.com --version 15 --mode production --apps erpnext,hrms --ssl --email your@email.com
```

**v16 with India Compliance:**
```bash
bash install_frappe.sh --site erp.example.com --version 16 --apps erpnext,india_compliance
```

**Custom passwords:**
```bash
bash install_frappe.sh --site erp.example.com --db-password MyDbP@ss --admin-password MyAdmin@123
```

When run as a one-liner, passwords are auto-generated and saved to `~/frappe_passwords.txt`.

---

## CLI Options

| Flag | Description | Default |
|------|-------------|---------|
| `--site`, `--domain` | Site domain (required) | — |
| `--version` | Frappe version: `14`, `15`, `16` | `15` |
| `--mode` | `development` or `production` | `development` |
| `--apps` | Comma-separated: `erpnext`, `hrms`, `india_compliance`, `crm`, `payments`, `wiki`, `helpdesk` | `erpnext` |
| `--db-password` | MariaDB root password | Auto-generated |
| `--admin-password` | ERPNext admin password | Auto-generated |
| `--ssl` | Enable Let's Encrypt SSL | Off |
| `--email` | Email for SSL/notifications | `admin@<site>` |
| `--help`, `-h` | Show help | — |

---

## Prerequisites

### 1. Create Server User

```bash
ssh root@your-server-ip
adduser frappe
usermod -aG sudo frappe
su - frappe
```

### 2. Download & Run

```bash
# Interactive mode (prompts for all values):
chmod +x install_frappe.sh
./install_frappe.sh

# Non-interactive (one-liner):
./install_frappe.sh --site erp.example.com --version 15
```

---

## Post-Installation

### Development Mode

```bash
cd ~/frappe-bench
bench start
# Access at http://your-domain:8000
```

### Production Mode

```bash
# Check status
supervisorctl status
nginx -t

# Restart if needed
bench restart
```

Credentials are saved to `~/frappe_passwords.txt` (chmod 600).

---

## Useful Commands

### Bench Commands

```bash
bench start                    # Start development server
bench restart                  # Restart production
bench backup                   # Create backup
bench update                  # Update ERPNext
bench migrate                 # Run migrations
bench console                 # Open Python console
```

### Service Management

```bash
# Supervisor
supervisorctl status
supervisorctl restart all

# Nginx
sudo nginx -t         # Test config
sudo nginx -s reload  # Reload

# MariaDB
sudo systemctl status mariadb
sudo systemctl restart mariadb
```

---

## Backup Configuration

```bash
# Manual backup
bench backup

# Backups location
ls ~/frappe-bench/sites/backups/
```

---

## SSL (Let's Encrypt)

```bash
# Via script (production mode):
./install_frappe.sh --site erp.example.com --mode production --ssl --email your@email.com

# Manual renewal:
sudo certbot renew
```

---

## Directory Structure

```
/home/frappe/
├── frappe-bench/          # Main ERPNext installation
│   ├── apps/              # ERPNext + Frappe source
│   ├── sites/             # Sites and backups
│   └── config/            # Nginx, Supervisor configs
└── frappe_passwords.txt   # Saved credentials (600 perms)
```

---

## System Requirements

| | Minimum | Recommended |
|---|---|---|
| RAM | 4 GB | 8+ GB |
| CPU | 2 cores | 4+ cores |
| Storage | 40 GB | SSD |

---

## Known Issues & Fixes

### Nginx "unknown log format main" Error

```bash
sudo sed -i '/http {/a\    include /etc/nginx/mime.types;' /etc/nginx/nginx.conf
sudo nginx -t
sudo service nginx restart
```

### MariaDB Authentication Error

```bash
sudo mysql -u root
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('your_password');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

### Bench Commands Not Found

```bash
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

---

## License

MIT License

## Support

- [ERPNext Forum](https://discuss.frappe.io)
- [Frappe Documentation](https://frappeframework.com/docs)

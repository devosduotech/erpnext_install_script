#!/bin/bash

###############################################################################
# Frappe/ERPNext Installation Script
# Version: 2.0.0
# Supports: Ubuntu 22.04, 24.04 LTS, Debian 11+
# Frappe Versions: v14, v15, v16
# Repo: https://github.com/devosduotech/erpnext_install_script
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NON_INTERACTIVE=false
SSL_EMAIL=""

generate_password() {
    openssl rand -hex 16 2>/dev/null || tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24
}

declare -A VERSION_CONFIG=(
    ["14"]="version-14|3.10|18|10.6|latest"
    ["15"]="version-15|3.11|18|10.6|latest"
    ["16"]="version-16|3.12|20|11.3|latest"
)

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║               Frappe/ERPNext Installation Script                     ║"
    echo "║                        v2.0.0                                        ║"
    echo "║                                                                   ║"
    echo "║  OS: Ubuntu 22.04, 24.04 LTS, Debian 11+                          ║"
    echo "║  Frappe: v14, v15, v16                                            ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

get_ubuntu_version() {
    lsb_release -rs 2>/dev/null || cat /etc/os-release | grep VERSION_ID | cut -d'"' -f2
}

get_debian_version() {
    cat /etc/debian_version | cut -d. -f1
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script must be run as a non-root user with sudo privileges"
        exit 1
    fi
    if ! sudo -v 2>/dev/null; then
        log_error "This script requires sudo privileges"
        exit 1
    fi
}

check_os_support() {
    log_info "Checking OS support..."
    OS_TYPE=""
    
    if command -v lsb_release &> /dev/null; then
        UBUNTU_VERSION=$(get_ubuntu_version)
        if [[ -n "$UBUNTU_VERSION" ]]; then
            if [[ "$UBUNTU_VERSION" == "22.04" || "$UBUNTU_VERSION" == "24.04" ]]; then
                OS_TYPE="ubuntu"
                log_info "Detected Ubuntu: $UBUNTU_VERSION"
            fi
        fi
    fi
    
    if [[ -z "$OS_TYPE" ]] && [[ -f /etc/debian_version ]]; then
        DEBIAN_VERSION=$(get_debian_version)
        if [[ "$DEBIAN_VERSION" -ge 11 ]]; then
            OS_TYPE="debian"
            log_info "Detected Debian: $DEBIAN_VERSION"
        fi
    fi
    
    if [[ -z "$OS_TYPE" ]]; then
        log_error "Unsupported OS. Supported: Ubuntu 22.04, 24.04, Debian 11+"
        exit 1
    fi
    
    export OS_TYPE
}

parse_cli_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --site|--domain)
                SITE_DOMAIN="$2"; shift 2 ;;
            --version)
                FRAPPE_VERSION="$2"; shift 2 ;;
            --mode)
                INSTALL_MODE="$2"; shift 2 ;;
            --db-password|--db-root-password)
                MARIADB_ROOT_PASSWORD="$2"; shift 2 ;;
            --admin-password)
                ADMIN_PASSWORD="$2"; shift 2 ;;
            --apps)
                SELECTED_APPS="$2"; shift 2 ;;
            --ssl)
                SETUP_SSL="y"; shift ;;
            --email)
                SSL_EMAIL="$2"; shift 2 ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "One-liner (fully non-interactive):"
                echo "  $0 --site erp.example.com --version 15 --mode production --apps erpnext,hrms"
                echo ""
                echo "Options:"
                echo "  --site, --domain        Site domain (required for non-interactive)"
                echo "  --version               Frappe version: 14, 15, 16 (default: 15)"
                echo "  --mode                  Install mode: development, production (default: development)"
                echo "  --db-password           MariaDB root password (auto-generated if not set)"
                echo "  --admin-password        ERPNext admin password (auto-generated if not set)"
                echo "  --apps                  Comma-separated apps: erpnext, hrms, india_compliance, crm, payments, wiki, helpdesk"
                echo "  --ssl                   Enable Let's Encrypt SSL (production only)"
                echo "  --email                 Email for SSL notifications"
                echo "  --help, -h              Show this help"
                echo ""
                echo "One-liner examples:"
                echo "  curl -s https://raw.githubusercontent.com/devosduotech/erpnext_install_script/main/install_frappe.sh | bash -s -- --site erp.example.com --version 15"
                echo "  wget -qO- https://raw.githubusercontent.com/devosduotech/erpnext_install_script/main/install_frappe.sh | bash -s -- --site erp.example.com --version 15 --mode production --apps erpnext,hrms"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Run '$0 --help' for usage"
                exit 1
                ;;
        esac
    done

    if [[ -n "$SITE_DOMAIN" ]]; then
        NON_INTERACTIVE=true
    fi

    if $NON_INTERACTIVE; then
        FRAPPE_VERSION="${FRAPPE_VERSION:-15}"
        INSTALL_MODE="${INSTALL_MODE:-development}"
        SETUP_SSL="${SETUP_SSL:-n}"
        SELECTED_APPS="${SELECTED_APPS:-erpnext}"
        MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-$(generate_password)}"
        ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(generate_password)}"
        SSL_EMAIL="${SSL_EMAIL:-admin@$SITE_DOMAIN}"
    fi
}

parse_version_config() {
    local version=$1
    local config="${VERSION_CONFIG[$version]}"
    FRAPPE_BRANCH=$(echo "$config" | cut -d'|' -f1)
    PYTHON_VERSION=$(echo "$config" | cut -d'|' -f2)
    NODE_VERSION=$(echo "$config" | cut -d'|' -f3)
    MARIADB_VERSION=$(echo "$config" | cut -d'|' -f4)
    BENCH_VERSION=$(echo "$config" | cut -d'|' -f5)
}

check_system_requirements() {
    log_info "Checking system requirements..."
    
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    log_info "Total RAM: ${TOTAL_RAM}GB"
    if [[ $TOTAL_RAM -lt 4 ]]; then
        log_warn "RAM is less than 4GB. ERPNext may not run optimally."
    fi
    if [[ $TOTAL_RAM -lt 8 ]]; then
        log_info "RAM under 8GB — checking swap..."
        if ! swapon --show | grep -q .; then
            log_info "Creating 4GB swap file..."
            sudo fallocate -l 4G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null
            sudo chmod 600 /swapfile
            sudo mkswap /swapfile
            sudo swapon /swapfile
            if ! grep -q '/swapfile' /etc/fstab; then
                echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
            fi
            log_success "Swap created"
        fi
    fi
    
    AVAILABLE_DISK=$(df -BG /home | awk 'NR==2 {print $4}' | tr -d 'G')
    log_info "Available disk space: ${AVAILABLE_DISK}GB"
    if [[ $AVAILABLE_DISK -lt 40 ]]; then
        log_warn "Disk space is less than 40GB."
    fi
}

get_user_inputs() {
    if $NON_INTERACTIVE; then
        parse_version_config "$FRAPPE_VERSION"
        log_info "Non-interactive mode: v$FRAPPE_VERSION ($FRAPPE_BRANCH), site=$SITE_DOMAIN, mode=$INSTALL_MODE, apps=$SELECTED_APPS"
        
        export FRAPPE_VERSION SITE_DOMAIN MARIADB_ROOT_PASSWORD ADMIN_PASSWORD
        export INSTALL_MODE SETUP_SSL SELECTED_APPS SSL_EMAIL
        export FRAPPE_BRANCH PYTHON_VERSION NODE_VERSION MARIADB_VERSION BENCH_VERSION
        return
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  Configuration"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""

    echo "Select Frappe Version:"
    echo "  [1] v14 (Legacy - Python 3.10, Node 18, MariaDB 10.6)"
    echo "  [2] v15 (Stable - Python 3.11, Node 18, MariaDB 10.6)"
    echo "  [3] v16 (Latest - Python 3.12, Node 20, MariaDB 11.3)"
    echo ""
    read -p "Enter version [1/2/3] (default: 2): " version_choice

    case "$version_choice" in
        1) FRAPPE_VERSION="14" ;;
        3) FRAPPE_VERSION="16" ;;
        *) FRAPPE_VERSION="15" ;;
    esac

    parse_version_config "$FRAPPE_VERSION"
    log_info "Selected Frappe v$FRAPPE_VERSION (Branch: $FRAPPE_BRANCH)"

    echo ""
    read -p "Enter site domain (e.g., erp.yourdomain.com): " SITE_DOMAIN
    if [[ -z "$SITE_DOMAIN" ]]; then
        log_error "Site domain is required"
        exit 1
    fi

    echo ""
    while true; do
        read -s -p "Enter MariaDB root password (leave empty to auto-generate): " MARIADB_ROOT_PASSWORD
        echo ""
        if [[ -z "$MARIADB_ROOT_PASSWORD" ]]; then
            MARIADB_ROOT_PASSWORD=$(generate_password)
            log_info "Auto-generated MariaDB password: $MARIADB_ROOT_PASSWORD"
            break
        fi
        read -s -p "Confirm MariaDB root password: " MARIADB_ROOT_PASSWORD_CONFIRM
        echo ""
        [[ "$MARIADB_ROOT_PASSWORD" == "$MARIADB_ROOT_PASSWORD_CONFIRM" ]] && break || log_error "Passwords do not match"
    done

    echo ""
    while true; do
        read -s -p "Enter ERPNext admin password (leave empty to auto-generate): " ADMIN_PASSWORD
        echo ""
        if [[ -z "$ADMIN_PASSWORD" ]]; then
            ADMIN_PASSWORD=$(generate_password)
            log_info "Auto-generated admin password: $ADMIN_PASSWORD"
            break
        fi
        if [[ ${#ADMIN_PASSWORD} -lt 8 ]]; then
            log_error "Password must be at least 8 characters"
            continue
        fi
        read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo ""
        [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]] && break || log_error "Passwords do not match"
    done

    echo ""
    echo "Installation Mode:"
    echo "  [1] Development (bench start required)"
    echo "  [2] Production (auto-starts with system)"
    read -p "Select mode [1/2] (default: 1): " INSTALL_MODE
    INSTALL_MODE=$([[ "$INSTALL_MODE" == "2" ]] && echo "production" || echo "development")

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  Select Additional Apps (comma-separated numbers)"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  [1] ERPnext (Core)"
    echo "  [2] HRMS"
    echo "  [3] India Compliance"
    echo "  [4] CRM"
    echo "  [5] Payments"
    echo "  [6] Wiki"
    echo "  [7] Helpdesk"
    echo ""
    read -p "Select apps [default: 1]: " app_selection

    SELECTED_APPS="erpnext"
    [[ "$app_selection" =~ [2] ]] && SELECTED_APPS="$SELECTED_APPS,hrms"
    [[ "$app_selection" =~ [3] ]] && SELECTED_APPS="$SELECTED_APPS,india_compliance"
    [[ "$app_selection" =~ [4] ]] && SELECTED_APPS="$SELECTED_APPS,crm"
    [[ "$app_selection" =~ [5] ]] && SELECTED_APPS="$SELECTED_APPS,payments"
    [[ "$app_selection" =~ [6] ]] && SELECTED_APPS="$SELECTED_APPS,wiki"
    [[ "$app_selection" =~ [7] ]] && SELECTED_APPS="$SELECTED_APPS,helpdesk"

    SETUP_SSL="n"
    SSL_EMAIL=""
    if [[ "$INSTALL_MODE" == "production" ]]; then
        echo ""
        read -p "Setup Let's Encrypt SSL? [y/N]: " setup_ssl_input
        if [[ "$setup_ssl_input" =~ [yY] ]]; then
            SETUP_SSL="y"
            read -p "Enter email for SSL notifications: " SSL_EMAIL
        fi
    fi
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  Installation Summary"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo -e "  Frappe Version:    v$FRAPPE_VERSION ($FRAPPE_BRANCH)"
    echo -e "  Bench Version:     $BENCH_VERSION"
    echo -e "  Python Version:    $PYTHON_VERSION"
    echo -e "  Node Version:      $NODE_VERSION"
    echo -e "  MariaDB Version:   $MARIADB_VERSION"
    echo -e "  Site Domain:       $SITE_DOMAIN"
    echo -e "  Installation Mode: $INSTALL_MODE"
    echo -e "  Selected Apps:     $SELECTED_APPS"
    echo -e "  SSL:               $([[ "$SETUP_SSL" == "y" ]] && echo "Yes" || echo "No")"
    echo ""

    if ! $NON_INTERACTIVE; then
        read -p "Proceed with installation? [y/N]: " confirm
        [[ "$confirm" =~ [yY] ]] || { log_info "Cancelled"; exit 0; }
    fi
    
    export FRAPPE_VERSION SITE_DOMAIN MARIADB_ROOT_PASSWORD ADMIN_PASSWORD
    export INSTALL_MODE SETUP_SSL SELECTED_APPS SSL_EMAIL
    export FRAPPE_BRANCH PYTHON_VERSION NODE_VERSION MARIADB_VERSION BENCH_VERSION
}

install_system_dependencies() {
    log_step "Installing system dependencies..."
    
    sudo apt update
    
    if ! command -v python${PYTHON_VERSION} &> /dev/null && [[ "$OS_TYPE" == "ubuntu" ]]; then
        log_info "Python $PYTHON_VERSION not found, adding deadsnakes PPA..."
        sudo add-apt-repository ppa:deadsnakes/ppa -y
    fi
    
    PYTHON_PKGS="python3-dev python3-setuptools python3-pip"
    if [[ "$FRAPPE_VERSION" == "14" ]]; then
        PYTHON_PKGS="$PYTHON_PKGS python3.10-venv python3.10-dev"
    elif [[ "$FRAPPE_VERSION" == "15" ]]; then
        PYTHON_PKGS="$PYTHON_PKGS python3.11-venv python3.11-dev"
    elif [[ "$FRAPPE_VERSION" == "16" ]]; then
        PYTHON_PKGS="$PYTHON_PKGS python3.12-venv python3.12-dev"
    fi
    
    sudo apt install -y \
        git curl wget vim htop software-properties-common \
        $PYTHON_PKGS \
        build-essential redis-server \
        libffi-dev libssl-dev libmariadb-dev libmariadb-dev-compat \
        libjpeg-dev zlib1g-dev xvfb libfontconfig1 \
        supervisor nginx \
        pkg-config \
        libldap2-dev libsasl2-dev libpq-dev \
        jq zip unzip dnsutils
    
    log_info "Installing wkhtmltopdf..."
    if ! command -v wkhtmltopdf &> /dev/null; then
        WKHTML_VER="0.12.6.1-2"
        WKHTML_DISTRO="jammy"
        [[ "$(lsb_release -rs 2>/dev/null)" == "24.04" ]] && WKHTML_DISTRO="noble"
        WKHTML_PACKAGE="wkhtmltox_${WKHTML_VER}.${WKHTML_DISTRO}_amd64.deb"
        WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTML_VER}/${WKHTML_PACKAGE}"
        log_info "Downloading: $WKHTML_URL"
        cd /tmp
        if wget -q "$WKHTML_URL" -O "$WKHTML_PACKAGE" 2>/dev/null && [[ -f "$WKHTML_PACKAGE" ]]; then
            sudo dpkg -i "$WKHTML_PACKAGE" 2>/dev/null || sudo apt --fix-broken install -y
            rm -f "$WKHTML_PACKAGE"
        else
            log_warn "wkhtmltopdf download failed, trying apt..."
            sudo apt install -y wkhtmltopdf 2>/dev/null || true
        fi
        cd - > /dev/null
        
        if command -v wkhtmltopdf &> /dev/null; then
            log_success "wkhtmltopdf installed: $(wkhtmltopdf --version 2>&1 | head -1)"
        else
            log_warn "wkhtmltopdf not installed — PDF generation may not work"
        fi
    else
        log_info "wkhtmltopdf already installed"
    fi
    
    log_info "Enabling Redis..."
    if systemctl list-unit-files | grep -q '^redis-server.service'; then
        sudo systemctl enable redis-server
        sudo systemctl start redis-server
    elif systemctl list-unit-files | grep -q '^redis.service'; then
        sudo systemctl enable redis
        sudo systemctl start redis
    else
        sudo systemctl enable redis-server 2>/dev/null || sudo systemctl enable redis 2>/dev/null || true
        sudo systemctl start redis-server 2>/dev/null || sudo systemctl start redis 2>/dev/null || true
    fi
    
    log_info "Installing cron (required for bench)..."
    sudo apt install -y cron
    sudo systemctl enable cron
    sudo systemctl start cron
    
    log_success "System dependencies installed"
}

setup_mariadb() {
    log_step "Setting up MariaDB..."
    
    if ! command -v mysql &> /dev/null; then
        UBUNTU_VER=$(lsb_release -rs 2>/dev/null)
        case "$UBUNTU_VER" in
            22.04) MARIADB_VERSION="${MARIADB_VERSION:-10.6}" ;;
            24.04) MARIADB_VERSION="${MARIADB_VERSION:-10.11}" ;;
        esac
        log_info "Target MariaDB version: $MARIADB_VERSION"
        
        if curl -sI "https://r.mariadb.com/downloads/mariadb_repo_setup" &>/dev/null; then
            log_info "Adding official MariaDB $MARIADB_VERSION repo..."
            curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-$MARIADB_VERSION" 2>/dev/null || {
                log_warn "MariaDB $MARIADB_VERSION repo failed, using system default"
                MARIADB_VERSION="system"
            }
        else
            MARIADB_VERSION="system"
        fi
        
        log_info "Installing MariaDB..."
        sudo apt update
        sudo apt install -y mariadb-server mariadb-client
    fi
    
    log_info "Starting MariaDB..."
    sudo systemctl start mariadb 2>/dev/null || sudo service mariadb start 2>/dev/null || sudo systemctl start mysql 2>/dev/null || true
    sleep 3
    
    log_info "Securing MariaDB..."
    sudo mysql -u root <<EOF
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    log_info "Configuring MariaDB..."
    
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    BUFFER_POOL=$((TOTAL_RAM / 2))
    [[ $BUFFER_POOL -lt 1 ]] && BUFFER_POOL=1
    [[ $BUFFER_POOL -gt 12 ]] && BUFFER_POOL=12
    log_info "InnoDB buffer pool: ${BUFFER_POOL}G"
    
    sudo tee /etc/mysql/mariadb.conf.d/50-frappe.cnf > /dev/null << EOF
[mysqld]
innodb-file-per-table=1
innodb-buffer-pool-size=${BUFFER_POOL}G
innodb-buffer-pool-instances=4
innodb-flush-log-at-trx-commit=2
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
bind-address = 127.0.0.1
max_connections = 500
skip-name-resolve

[mysql]
default-character-set = utf8mb4
EOF
    
    sudo systemctl restart mariadb 2>/dev/null || sudo systemctl restart mysql 2>/dev/null || sudo service mariadb restart 2>/dev/null || true
    sleep 2
    
    log_info "Configuring MariaDB root user..."
    sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('$MARIADB_ROOT_PASSWORD');
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    
    log_success "MariaDB configured"
}

install_nodejs() {
    log_step "Installing Node.js $NODE_VERSION..."
    
    if [[ ! -d "$HOME/.nvm" ]]; then
        log_info "Installing NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
    fi
    
    export NVM_DIR="$HOME/.nvm"
    [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
    
    nvm install $NODE_VERSION
    nvm use $NODE_VERSION
    nvm alias default $NODE_VERSION

    log_info "Installing Yarn..."
    npm install -g yarn
    
    log_success "Node.js installed"
}

install_bench() {
    log_step "Installing Frappe Bench..."
    
    log_info "Upgrading pip..."
    pip3 install --upgrade pip --user 2>/dev/null || true
    
    PIP_VERSION=$(pip3 --version | awk '{print $2}')
    PIP_MAJOR=$(echo "$PIP_VERSION" | cut -d. -f1)
    PIP_MINOR=$(echo "$PIP_VERSION" | cut -d. -f2)
    
    PIP_FLAGS="--user"
    if [[ $PIP_MAJOR -gt 23 ]] || [[ $PIP_MAJOR -eq 23 && $PIP_MINOR -ge 1 ]]; then
        PIP_FLAGS="--break-system-packages --user"
    fi
    
    log_info "Using pip version: $PIP_VERSION with flags: $PIP_FLAGS"
    
    log_info "Installing frappe-bench..."
    pip3 install frappe-bench $PIP_FLAGS
    
    export PATH="$HOME/.local/bin:$PATH"
    if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    
    if ! command -v bench &> /dev/null; then
        log_error "Bench installation failed"
        exit 1
    fi
    
    git config --global url."https://github.com/".insteadOf ssh://git@github.com/
    git config --global url."https://github.com/".insteadOf git@github.com:
    
    log_success "Bench installed"
}

ensure_nvm() {
    export NVM_DIR="$HOME/.nvm"
    [[ -d "$NVM_DIR" ]] && [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
    nvm use $NODE_VERSION
}

ensure_path() {
    export PATH="$HOME/.local/bin:$PATH"
    if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
}

initialize_bench() {
    log_step "Initializing Frappe Bench..."
    
    cd "$HOME"
    ensure_nvm
    ensure_path
    
    [[ -d "$HOME/frappe-bench" ]] && rm -rf "$HOME/frappe-bench"
    
    local python_cmd="/usr/bin/python${PYTHON_VERSION}"
    log_info "Running: bench init frappe-bench --frappe-branch $FRAPPE_BRANCH --python $python_cmd"
    bench init frappe-bench --frappe-branch "$FRAPPE_BRANCH" --python "$python_cmd"
    
    if [[ ! -d "$HOME/frappe-bench/apps/frappe" ]]; then
        log_error "Bench initialization failed"
        exit 1
    fi
    
    cd frappe-bench
    
    log_info "Setting permissions for bench..."
    chmod -R 755 "$HOME/frappe-bench"
    
    bench config dns_multitenant on
    bench config restart_supervisor_on_update off
    bench config restart_systemd_on_update off
    
    log_success "Bench initialized"
}

install_apps() {
    log_step "Installing selected apps..."
    
    cd "$HOME/frappe-bench"
    ensure_nvm
    ensure_path

    IFS=',' read -ra APPS <<< "$SELECTED_APPS"
    for app in "${APPS[@]}"; do
        case "$app" in
            erpnext)
                log_info "Getting ERPNext..."
                bench get-app erpnext --branch "$FRAPPE_BRANCH"
                ;;
            hrms)
                log_info "Getting HRMS..."
                bench get-app hrms --branch "$FRAPPE_BRANCH"
                ;;
            india_compliance)
                log_info "Getting India Compliance..."
                bench get-app https://github.com/resilient-tech/india-compliance.git --branch "$FRAPPE_BRANCH"
                ;;
            crm)
                log_info "Getting CRM..."
                bench get-app https://github.com/frappe/crm.git --branch "$FRAPPE_BRANCH"
                ;;
            payments)
                log_info "Getting Payments..."
                bench get-app payments --branch "$FRAPPE_BRANCH"
                ;;
            wiki)
                log_info "Getting Wiki..."
                bench get-app https://github.com/frappe/wiki.git --branch "$FRAPPE_BRANCH"
                ;;
            helpdesk)
                log_info "Getting Helpdesk..."
                bench get-app https://github.com/frappe/helpdesk.git --branch "$FRAPPE_BRANCH"
                ;;
        esac
    done
    
    log_success "Apps downloaded"
}

create_site() {
    log_step "Creating site: $SITE_DOMAIN..."
    
    cd "$HOME/frappe-bench"
    ensure_nvm
    ensure_path

    bench new-site "$SITE_DOMAIN" \
        --db-password "$MARIADB_ROOT_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD"
    
    IFS=',' read -ra APPS <<< "$SELECTED_APPS"
    for app in "${APPS[@]}"; do
        log_info "Installing $app..."
        bench --site "$SITE_DOMAIN" install-app "$app"
    done
    
    bench --site "$SITE_DOMAIN" enable-scheduler
    
    log_success "Site created: $SITE_DOMAIN"
    
    if [[ "$INSTALL_MODE" == "production" ]]; then
        log_info "Building assets (required for production)..."
        bench build
    fi
}

setup_production() {
    [[ "$INSTALL_MODE" != "production" ]] && return
    
    log_step "Setting up production..."
    
    cd "$HOME/frappe-bench"
    ensure_nvm
    ensure_path
    
    log_info "Running bench setup production..."
    bench setup production "$USER" --yes
    
    log_info "Fixing nginx config for Frappe..."
    if ! grep -q "include /etc/nginx/mime.types;" /etc/nginx/nginx.conf 2>/dev/null; then
        sudo sed -i '/http {/a\    include /etc/nginx/mime.types;\n    default_type application/octet-stream;' /etc/nginx/nginx.conf
    fi
    
    sudo nginx -t || {
        log_warn "Nginx config test failed, attempting to fix..."
        if ! grep -q "include /etc/nginx/mime.types;" /etc/nginx/nginx.conf 2>/dev/null; then
            sudo sed -i '/http {/a\    include /etc/nginx/mime.types;\n    default_type application/octet-stream;' /etc/nginx/nginx.conf
        fi
        sudo nginx -t
    }
    sudo service nginx start || sudo nginx
    sudo supervisorctl restart all
    
    log_success "Production setup complete"
}

setup_ssl() {
    [[ "$SETUP_SSL" != "y" ]] && return
    
    log_step "Setting up SSL..."
    
    log_info "Checking DNS for $SITE_DOMAIN..."
    if ! host "$SITE_DOMAIN" &>/dev/null && ! dig +short "$SITE_DOMAIN" &>/dev/null; then
        log_warn "DNS not resolving for $SITE_DOMAIN. SSL setup skipped."
        return
    fi
    
    if ! command -v certbot &> /dev/null; then
        sudo apt install -y certbot python3-certbot-nginx
    fi
    
    if [[ -n "$SSL_EMAIL" ]]; then
        sudo certbot --nginx -d "$SITE_DOMAIN" --non-interactive --agree-tos --email "$SSL_EMAIL" || {
            log_warn "SSL setup failed. Run manually: sudo certbot --nginx -d $SITE_DOMAIN"
        }
    else
        sudo certbot --nginx -d "$SITE_DOMAIN" || {
            log_warn "SSL setup failed. Run manually: sudo certbot --nginx -d $SITE_DOMAIN"
        }
    fi
    
    log_success "SSL configured"
}

save_passwords() {
    local pwfile="$HOME/frappe_passwords.txt"
    cat > "$pwfile" << EOF
═══════════════════════════════════════════
  ERPNext Installation Credentials
  Site: $SITE_DOMAIN
═══════════════════════════════════════════

MariaDB root user:  root
MariaDB password:   $MARIADB_ROOT_PASSWORD

ERPNext Admin user: Administrator
ERPNext password:   $ADMIN_PASSWORD

Save this file securely and delete after noting.
═══════════════════════════════════════════
EOF
    chmod 600 "$pwfile"
}

run_health_check() {
    log_step "Running health checks..."
    cd "$HOME/frappe-bench" 2>/dev/null || return
    ensure_nvm
    ensure_path

    local checks_passed=0 checks_total=0
    
    check() {
        local label="$1"; shift
        checks_total=$((checks_total + 1))
        if "$@" &>/dev/null; then
            echo -e "  ${GREEN}OK${NC}    $label"
            checks_passed=$((checks_passed + 1))
        else
            echo -e "  ${RED}WARN${NC}  $label"
        fi
    }

    echo ""
    check "MariaDB running"    sudo systemctl is-active mariadb 2>/dev/null || sudo systemctl is-active mysql
    check "Redis running"      sudo systemctl is-active redis-server 2>/dev/null || sudo systemctl is-active redis
    check "Nginx installed"    command -v nginx
    check "Site directory"     test -d "$HOME/frappe-bench/sites/$SITE_DOMAIN"
    check "Frappe app"         test -d "$HOME/frappe-bench/apps/frappe"
    check "Bench CLI"          bench --version
    check "Bench doctor"       bench doctor 2>/dev/null || true

    if [[ "$INSTALL_MODE" == "production" ]]; then
        check "Supervisor running" sudo supervisorctl status 2>/dev/null
        check "Nginx running"      sudo nginx -t 2>/dev/null
    fi

    echo ""
    log_info "Health check: $checks_passed/$checks_total passed"
}

installation_complete() {
    save_passwords
    run_health_check
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo -e "  ${GREEN}Installation Complete!${NC}"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    
    if [[ "$INSTALL_MODE" == "development" ]]; then
        echo "  To start: cd ~/frappe-bench && bench start"
        echo "  Access: http://$SITE_DOMAIN:8000"
    else
        [[ "$SETUP_SSL" == "y" ]] && echo "  Access: https://$SITE_DOMAIN" || echo "  Access: http://$SITE_DOMAIN"
    fi
    echo ""
    echo "  Admin Login: Administrator"
    echo "  Password:    $ADMIN_PASSWORD"
    echo ""
    echo "  Credentials saved to: $HOME/frappe_passwords.txt"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
}

main() {
    parse_cli_args "$@"
    print_banner
    check_root
    check_os_support
    check_system_requirements
    get_user_inputs
    install_system_dependencies
    setup_mariadb
    install_nodejs
    install_bench
    initialize_bench
    install_apps
    create_site
    setup_production
    setup_ssl
    installation_complete
}

main "$@"

#!/bin/bash

###############################################################################
# Frappe/ERPNext Database Optimization Script
# Version: 2.0.0
# Run on existing production servers to optimize MariaDB performance
# Repo: https://github.com/devosduotech/erpnext_install_script
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║          Frappe/ERPNext Database Optimization Script               ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_memory() {
    TOTAL_RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    log_info "Total RAM: ${TOTAL_RAM_GB}GB"
}

optimize_mariadb_config() {
    log_info "Optimizing MariaDB configuration..."
    
    detect_memory
    
    BUFFER_POOL_MB=$((TOTAL_RAM_MB * 80 / 100))
    if [[ $BUFFER_POOL_MB -lt 512 ]]; then
        BUFFER_POOL_MB=512
    fi
    
    BUFFER_POOL_INSTANCES=1
    if [[ $TOTAL_RAM_GB -ge 64 ]]; then
        BUFFER_POOL_MB=51200
        BUFFER_POOL_INSTANCES=16
    elif [[ $TOTAL_RAM_GB -ge 32 ]]; then
        BUFFER_POOL_MB=25600
        BUFFER_POOL_INSTANCES=8
    elif [[ $TOTAL_RAM_GB -ge 16 ]]; then
        BUFFER_POOL_MB=12288
        BUFFER_POOL_INSTANCES=4
    elif [[ $TOTAL_RAM_GB -ge 8 ]]; then
        BUFFER_POOL_MB=6144
        BUFFER_POOL_INSTANCES=4
    elif [[ $TOTAL_RAM_GB -ge 4 ]]; then
        BUFFER_POOL_INSTANCES=2
    fi
    
    log_info "Setting InnoDB buffer pool size: ${BUFFER_POOL_MB}MB (${BUFFER_POOL_INSTANCES} instances)"
    
    cat > /etc/mysql/conf.d/frappe-optimized.cnf << EOF
[mysqld]
character-set-client-handshake = FALSE
init-connect = 'SET NAMES utf8mb4'
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

bind-address = 0.0.0.0
innodb-file-per-table = 1
innodb-buffer-pool-size = ${BUFFER_POOL_MB}M
innodb-buffer-pool-instances = ${BUFFER_POOL_INSTANCES}
innodb-log-file-size = 256M
innodb-log-buffer-size = 64M
innodb-flush-log-at-trx-commit = 2
innodb-flush-method = O_DIRECT
innodb-file-per-table = 1
innodb-io-capacity = 2000
innodb-io-capacity-max = 6000
innodb-read-io-threads = 16
innodb-write-io-threads = 16
innodb-thread-concurrency = 0

max_connections = 500
max-allowed-packet = 256M
max-connect-errors = 1000000

skip-name-resolve
lower_case_table_names = 1

query-cache-type = 0
query-cache-size = 0

slow-query-log = 1
slow-query-log-file = /var/lib/mysql/mysql-slow.log
long-query-time = 2

tmp-table-size = 256M
max-heap-table-size = 256M

thread-cache-size = 50
table-open-cache = 4000
table-definition-cache = 2000

[mysql]
default-character-set = utf8mb4

[client]
default-character-set = utf8mb4

[mysqldump]
quick
max_allowed_packet = 256M
EOF
    
    log_success "MariaDB configuration optimized"
}

optimize_mariadb() {
    log_info "Applying MariaDB optimizations..."
    
    sudo service mysql restart 2>/dev/null || sudo systemctl restart mariadb 2>/dev/null || sudo systemctl restart mysql 2>/dev/null
    
    sleep 3
    
    log_success "MariaDB restarted with new configuration"
}

create_optimization_indexes() {
    log_info "Creating recommended indexes for ERPNext..."
    
    BENCH_DIR="$HOME/frappe-bench"
    SITE_NAME=$(ls "$BENCH_DIR/sites" 2>/dev/null | head -1)
    
    if [[ -z "$SITE_NAME" ]] || [[ ! -d "$BENCH_DIR/sites/$SITE_NAME" ]]; then
        log_warn "Could not detect Frappe site. Skipping index creation."
        return
    fi
    
    log_info "Detected site: $SITE_NAME"
    
    cd "$BENCH_DIR"
    
    if command -v bench &> /dev/null; then
        export PATH="$HOME/.local/bin:$PATH"
        export NVM_DIR="$HOME/.nvm"
        [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
        
        log_info "Running bench console to create indexes..."
        
        bench --site "$SITE_NAME" execute - << 'PYEOF'
import frappe
from frappe.model.db_schema import add_index

frappe.flags.inMigration = True

try:
    add_index("GL Entry", ["company", "posting_date", "account", "voucher_type", "voucher_no", "is_cancelled"], "idx_gl_company_posting")
    frappe.db.commit()
    print("Index created: idx_gl_company_posting")
except Exception as e:
    print(f"Index creation skipped: {e}")

frappe.flags.inMigration = False
PYEOF
    fi
    
    log_success "Index optimization complete"
}

configure_gunicorn_workers() {
    log_info "Optimizing Gunicorn workers..."
    
    BENCH_DIR="$HOME/frappe-bench"
    
    if [[ ! -d "$BENCH_DIR" ]]; then
        log_warn "Frappe bench not found. Skipping Gunicorn optimization."
        return
    fi
    
    NUM_CORES=$(nproc 2>/dev/null || echo 4)
    WORKERS=$((NUM_CORES * 2 + 1))
    
    log_info "Detected $NUM_CORES cores, setting $WORKERS workers"
    
    cd "$BENCH_DIR"
    export PATH="$HOME/.local/bin:$PATH"
    
    bench set-config -g gunicorn_workers "$WORKERS" 2>/dev/null || true
    bench set-config -g gunicorn_worker_class sync 2>/dev/null || true
    bench set-config -g gunicorn_worker_tmp_dir /dev/shm 2>/dev/null || true
    bench set-config -g gunicorn_max_requests 1000 2>/dev/null || true
    bench set-config -g gunicorn_max_requests_jitter 50 2>/dev/null || true
    bench set-config -g background_workers 1 2>/dev/null || true
    bench set-config -g frappe_worker_count "$NUM_CORES" 2>/dev/null || true
    
    log_success "Gunicorn workers optimized"
}

optimize_redis() {
    log_info "Optimizing Redis configuration..."
    
    REDIS_MEMORY_MB=$(free -m | awk '/^Mem:/{print int($2 * 0.7)}')
    
    sudo tee /etc/redis/redis.conf.d/frappe-optimized.conf > /dev/null << EOF
maxmemory ${REDIS_MEMORY_MB}mb
maxmemory-policy allkeys-lru
EOF
    
    sudo service redis-server restart 2>/dev/null || sudo systemctl restart redis 2>/dev/null || true
    
    log_success "Redis optimized"
}

print_recommendations() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "  Post-Optimization Recommendations"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  1. Monitor slow queries:"
    echo "     sudo mysql -e 'SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 10;'"
    echo ""
    echo "  2. Monitor database connections:"
    echo "     sudo mysql -e 'SHOW STATUS LIKE \"Threads_connected\";'"
    echo ""
    echo "  3. Check buffer pool usage:"
    echo "     sudo mysql -e 'SHOW STATUS LIKE \"Innodb_buffer_pool%\";'"
    echo ""
    echo "  4. For heavy workloads, consider:"
    echo "     - Separate database server"
    echo "     - SSD storage for database"
    echo "     - More RAM"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
}

main() {
    print_banner
    check_root
    
    log_info "Starting database optimization..."
    
    optimize_mariadb_config
    optimize_mariadb
    
    if [[ -d "$HOME/frappe-bench" ]]; then
        configure_gunicorn_workers
        create_optimization_indexes
    else
        log_warn "Frappe bench not found at ~/frappe-bench. Skipping app-specific optimizations."
    fi
    
    log_success "Database optimization complete!"
    print_recommendations
}

main "$@"

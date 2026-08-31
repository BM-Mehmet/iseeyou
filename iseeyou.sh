#!/bin/bash

# ============================================
# Zabbix 7.0 LTS + TimescaleDB Kurulum Scripti
# Ubuntu 24.04 (Noble)
# TimescaleDB 2.29.2 ile test edilmiştir
# ============================================

set -e

# --- DEĞİŞKENLER ---
DB_PASSWORD="Ubuntu123."  # Değiştirin!
DB_NAME="zabbix"
DB_USER="zabbix"
PG_VER="16"
TIMESCALE_COMPRESS_DAYS=7
TIMESCALE_COMPRESS_TRENDS_DAYS=30

# --- RENKLER ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- FONKSİYONLAR ---
print_status() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN} $1${NC}"
}

print_error() {
    echo -e "${RED} HATA: $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}  $1${NC}"
}

# --- 1. REPOLAR ---
print_status "1. Repolar Güncelleniyor"

sudo apt update
sudo apt install -y wget curl gnupg software-properties-common

print_success "Repolar güncellendi"

# --- 2. ZABBIX REPO ---
print_status "2. Zabbix 7.0 LTS Reposu Ekleniyor"

wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo apt update 

print_success "Zabbix reposu eklendi"

# --- 3. TIMESCALEDB REPO ---
print_status "3. TimescaleDB Reposu Ekleniyor"

curl -s -L https://packagecloud.io/timescale/timescaledb/gpgkey | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/timescaledb.gpg
echo "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ noble main" | sudo tee /etc/apt/sources.list.d/timescaledb.list
sudo apt update 

print_success "TimescaleDB reposu eklendi"

# --- 4. PAKET KURULUMU ---
print_status "4. Paketler Kuruluyor"

sudo apt install -y \
    zabbix-server-pgsql \
    zabbix-frontend-php \
    php8.3-pgsql \
    zabbix-nginx-conf \
    zabbix-sql-scripts \
    zabbix-agent2 \
    postgresql-${PG_VER} \
    postgresql-contrib \
    timescaledb-2-postgresql-${PG_VER} \
    nginx \
    php8.3-fpm

print_success "Paketler kuruldu"

# --- 5. POSTGRESQL + TIMESCALEDB ---
print_status "5. PostgreSQL ve TimescaleDB Yapılandırılıyor"

sudo systemctl stop postgresql

sudo tee /etc/postgresql/${PG_VER}/main/postgresql.conf > /dev/null <<EOL
data_directory = '/var/lib/postgresql/${PG_VER}/main'
hba_file = '/etc/postgresql/${PG_VER}/main/pg_hba.conf'
ident_file = '/etc/postgresql/${PG_VER}/main/pg_ident.conf'
external_pid_file = '/var/run/postgresql/${PG_VER}-main.pid'
listen_addresses = 'localhost'
port = 5432
max_connections = 1000
shared_buffers = 512MB
work_mem = 32MB
maintenance_work_mem = 256MB
effective_cache_size = 2GB
shared_preload_libraries = 'timescaledb'
EOL

sudo systemctl start postgresql

print_success "PostgreSQL yapılandırıldı"

# --- 6. VERİTABANI ---
print_status "6. Veritabanı Oluşturuluyor"

sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" 2>/dev/null || true

sudo -u postgres psql -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true
sudo -u postgres psql -c "DROP USER IF EXISTS $DB_USER;" 2>/dev/null || true
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"

print_success "Veritabanı oluşturuldu"

# --- 7. ZABBIX ŞEMA ---
print_status "7. Zabbix Şeması Yükleniyor (Bu işlem uzun sürebilir)"

zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u $DB_USER PGPASSWORD=$DB_PASSWORD psql $DB_NAME

print_success "Zabbix şeması yüklendi"

# --- 8. TIMESCALEDB HYPERTABLE ---
print_status "8. TimescaleDB Hypertable Oluşturuluyor"

sudo -u $DB_USER PGPASSWORD=$DB_PASSWORD psql $DB_NAME <<EOF
SELECT create_hypertable('history', 'clock', chunk_time_interval => 86400, if_not_exists => TRUE);
SELECT create_hypertable('history_uint', 'clock', chunk_time_interval => 86400, if_not_exists => TRUE);
SELECT create_hypertable('history_str', 'clock', chunk_time_interval => 86400, if_not_exists => TRUE);
SELECT create_hypertable('history_log', 'clock', chunk_time_interval => 86400, if_not_exists => TRUE);
SELECT create_hypertable('history_text', 'clock', chunk_time_interval => 86400, if_not_exists => TRUE);
SELECT create_hypertable('trends', 'clock', chunk_time_interval => 86400, if_not_exists => TRUE);
SELECT create_hypertable('trends_uint', 'clock', chunk_time_interval => 86400, if_not_exists => TRUE);
EOF

print_success "Hypertable'lar oluşturuldu"

# --- 9. TIMESCALEDB COMPRESSION ---
print_status "9. Compression Aktif Ediliyor"

sudo -u $DB_USER PGPASSWORD=$DB_PASSWORD psql $DB_NAME <<EOF
ALTER TABLE history SET (timescaledb.compress = true);
ALTER TABLE history_uint SET (timescaledb.compress = true);
ALTER TABLE history_str SET (timescaledb.compress = true);
ALTER TABLE history_log SET (timescaledb.compress = true);
ALTER TABLE history_text SET (timescaledb.compress = true);
ALTER TABLE trends SET (timescaledb.compress = true);
ALTER TABLE trends_uint SET (timescaledb.compress = true);
EOF

print_success "Compression aktif edildi"

# --- 10. COMPRESSION POLİTİKALARI ---
print_status "10. Compression Politikaları Ekleniyor"

COMPRESS_AFTER=$((TIMESCALE_COMPRESS_DAYS * 86400))
COMPRESS_AFTER_TRENDS=$((TIMESCALE_COMPRESS_TRENDS_DAYS * 86400))

sudo -u $DB_USER PGPASSWORD=$DB_PASSWORD psql $DB_NAME <<EOF
SELECT add_compression_policy('history', compress_after => ${COMPRESS_AFTER}, if_not_exists => TRUE);
SELECT add_compression_policy('history_uint', compress_after => ${COMPRESS_AFTER}, if_not_exists => TRUE);
SELECT add_compression_policy('history_str', compress_after => ${COMPRESS_AFTER}, if_not_exists => TRUE);
SELECT add_compression_policy('history_log', compress_after => ${COMPRESS_AFTER}, if_not_exists => TRUE);
SELECT add_compression_policy('history_text', compress_after => ${COMPRESS_AFTER}, if_not_exists => TRUE);
SELECT add_compression_policy('trends', compress_after => ${COMPRESS_AFTER_TRENDS}, if_not_exists => TRUE);
SELECT add_compression_policy('trends_uint', compress_after => ${COMPRESS_AFTER_TRENDS}, if_not_exists => TRUE);
EOF

print_success "Compression politikaları eklendi"

# --- 11. ZABBIX SERVER ---
print_status "11. Zabbix Server Yapılandırılıyor"

sudo sed -i "s/# DBPassword=/DBPassword=$DB_PASSWORD/g" /etc/zabbix/zabbix_server.conf

sudo tee -a /etc/zabbix/zabbix_server.conf > /dev/null <<EOL

# ===== PERFORMANS AYARLARI =====
StartPollers=10
StartPollersUnreachable=5
StartTrappers=10
StartPingers=3
StartDiscoverers=2
StartHTTPPollers=2
CacheSize=64M
HistoryCacheSize=32M
ValueCacheSize=16M
EOL

print_success "Zabbix Server yapılandırıldı"

# --- 12. NGINX ---
print_status "12. Nginx Yapılandırılıyor"

sudo sed -i 's/# listen 80;/listen 80;/g' /etc/zabbix/nginx.conf
sudo sed -i 's/# server_name example.com;/server_name _;/g' /etc/zabbix/nginx.conf

sudo rm -f /etc/nginx/sites-enabled/default

print_success "Nginx yapılandırıldı"

# --- 13. PHP ---
print_status "13. PHP Yapılandırılıyor"

sudo sed -i 's/memory_limit = .*/memory_limit = 256M/g' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/g' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/max_input_time = .*/max_input_time = 300/g' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 20M/g' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 20M/g' /etc/php/8.3/fpm/php.ini

print_success "PHP yapılandırıldı"

# --- 14. SERVİSLER ---
print_status "14. Servisler Başlatılıyor"

sudo systemctl restart postgresql
sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.3-fpm
sudo systemctl enable postgresql zabbix-server zabbix-agent2 nginx php8.3-fpm

print_success "Servisler başlatıldı"

# --- 15. BAĞLANTI TESTİ ---
print_status "15. Bağlantı Testi"

if sudo -u $DB_USER PGPASSWORD=$DB_PASSWORD psql -d $DB_NAME -c "SELECT 1;" &>/dev/null; then
    print_success "Veritabanı bağlantısı başarılı!"
else
    print_warning "Veritabanı bağlantısı başarısız!"
fi

# --- 16. BİLGİ ---
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "========================================="
echo -e "${GREEN} KURULUM BAŞARIYLA TAMAMLANDI!${NC}"
echo "========================================="
echo ""
echo "   Web Arayüzü: http://$IP"
echo "   Kullanıcı: Admin"
echo "   Şifre: zabbix"
echo ""
echo "   Veritabanı: $DB_NAME"
echo "   Veritabanı Kullanıcısı: $DB_USER"
echo "   Veritabanı Şifresi: $DB_PASSWORD"
echo "   PostgreSQL Sürümü: $PG_VER"
echo "   Web arayüzünü açın: http://$IP"
echo "   Giriş yapın: Admin / zabbix"
echo ""
echo "    Compression: ${TIMESCALE_COMPRESS_DAYS} gün (history)"
echo "    Compression: ${TIMESCALE_COMPRESS_TRENDS_DAYS} gün (trends)"
echo ""
echo "========================================="



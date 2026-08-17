#!/bin/bash

# Zabbix 7.0 LTS Otomatik Kurulum Scripti (Ubuntu 24.04)
# Veritabanı: PostgreSQL 16 + TimescaleDB
# Optimize edilmiş bağlantı ayarları ile

set -e

# --- DEĞİŞKENLER ---
DB_PASSWORD="Ubuntu123." # Bunu mutlaka değiştir!
DB_NAME="zabbix"
DB_USER="zabbix"
PG_VER="16"  # Ubuntu 24.04 için sabit sürüm

echo "--- 1. Repolar Güncelleniyor ve Gereklilikler Kuruluyor ---"
sudo apt update && sudo apt install -y wget curl gpg

echo "--- 2. Zabbix 7.0 LTS Reposu Ekleniyor ---"
wget https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo dpkg -i zabbix-release_7.0-1+ubuntu24.04_all.deb
sudo apt update

echo "--- 3. TimescaleDB Reposu Ekleniyor ---"
curl -L https://packagecloud.io/timescale/timescaledb/gpgkey | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/timescaledb.gpg
echo "deb https://packagecloud.io/timescale/timescaledb/ubuntu/ noble main" | sudo tee /etc/apt/sources.list.d/timescaledb.list
sudo apt update

echo "--- 4. Paketler Kuruluyor (Zabbix, PostgreSQL 16, TimescaleDB, Nginx) ---"
sudo apt install -y \
    zabbix-server-pgsql \
    zabbix-frontend-php \
    php8.3-pgsql \
    zabbix-nginx-conf \
    zabbix-sql-scripts \
    zabbix-agent2 \
    postgresql-${PG_VER} \
    postgresql-contrib-${PG_VER} \
    timescaledb-2-postgresql-${PG_VER} \
    nginx

# TimescaleDB paketinin doğru kurulduğunu kontrol et
if [ $? -ne 0 ]; then
    echo "TimescaleDB kurulumu başarısız oldu. Alternatif paket deneniyor..."
    sudo apt install -y timescaledb-postgresql-${PG_VER}
fi

echo "--- 5. PostgreSQL Optimizasyonu (Bağlantı Havuzu Sorunları İçin) ---"
# PostgreSQL konfigürasyonunu optimize et
sudo tee -a /etc/postgresql/${PG_VER}/main/postgresql.conf > /dev/null <<EOL
# Zabbix Optimizasyon Ayarları
max_connections = 500
shared_buffers = 256MB
work_mem = 16MB
maintenance_work_mem = 128MB
effective_cache_size = 1GB
EOL

echo "--- 6. Veritabanı Yapılandırması ---"
# TimescaleDB ayarını postgresql.conf'a ekle
sudo timescaledb-tune --quiet --yes || true

# Postgres'i yeniden başlat
sudo systemctl restart postgresql

# Kullanıcı ve DB oluştur
sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;" 2>/dev/null || true
sudo -u postgres psql -d $DB_NAME -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" 2>/dev/null || true

echo "--- 7. Şema İçe Aktarımı (Bu işlem biraz vakit alabilir) ---"
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | sudo -u $DB_USER PGPASSWORD=$DB_PASSWORD psql $DB_NAME

echo "--- 8. TimescaleDB Optimizasyon Şeması ---"
if [ -f /usr/share/zabbix-sql-scripts/postgresql/timescaledb.sql.gz ]; then
    zcat /usr/share/zabbix-sql-scripts/postgresql/timescaledb.sql.gz | sudo -u $DB_USER PGPASSWORD=$DB_PASSWORD psql $DB_NAME
else
    echo "TimescaleDB optimizasyon şeması bulunamadı, atlanıyor..."
fi

echo "--- 9. Zabbix Server Konfigürasyonu ---"
# Zabbix server konfigürasyonunu optimize et
sudo sed -i "s/# DBPassword=/DBPassword=$DB_PASSWORD/g" /etc/zabbix/zabbix_server.conf

# Zabbix bağlantı ayarlarını optimize et
sudo tee -a /etc/zabbix/zabbix_server.conf > /dev/null <<EOL
# Optimizasyon Ayarları
StartPollers=5
StartPollersUnreachable=1
StartTrappers=5
StartPingers=1
StartDiscoverers=1
StartHTTPPollers=1
StartTimers=1
StartEscalators=1
StartAlerters=3
StartProxyPollers=1
StartLLDProcessors=1
CacheSize=32M
HistoryCacheSize=16M
TrendCacheSize=4M
ValueCacheSize=8M
EOL

echo "--- 10. Nginx Konfigürasyonu ---"
sudo sed -i 's/# listen 80;/listen 80;/g' /etc/zabbix/nginx.conf
sudo sed -i 's/# server_name example.com;/server_name _;/g' /etc/zabbix/nginx.conf

echo "--- 11. PHP Konfigürasyonu ---"
# PHP ayarlarını optimize et
sudo sed -i 's/memory_limit = .*/memory_limit = 256M/g' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/post_max_size = .*/post_max_size = 16M/g' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 20M/g' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/^;date.timezone =.*/date.timezone = Europe\/Istanbul/' /etc/php/8.3/fpm/php.ini
sudo sed -i 's/^;date.timezone =.*/date.timezone = Europe\/Istanbul/' /etc/php/8.3/cli/php.ini

echo "--- 12. Servisler Başlatılıyor ---"
sudo systemctl restart postgresql
sudo systemctl restart zabbix-server zabbix-agent2 nginx php8.3-fpm
sudo systemctl enable postgresql
sudo systemctl enable zabbix-server zabbix-agent2 nginx php8.3-fpm

# Varsayılan Nginx sayfasını kaldır
sudo rm -f /etc/nginx/sites-enabled/default

# Nginx'i yeniden başlat
sudo systemctl restart nginx

echo "-------------------------------------------------------"
echo " KURULUM TAMAMLANDI!"
echo " Kullanıcı adı: Admin"
echo " Şifre: zabbix"
echo " Web Arayüzü: http://$(hostname -I | awk '{print $1}')"
echo " Veritabanı Şifren: $DB_PASSWORD"
echo " PostgreSQL Sürümü: $PG_VER"
echo "-------------------------------------------------------"

echo ""
echo "--- Servis Durumları ---"
echo "PostgreSQL:"
systemctl status postgresql --no-pager | grep "Active:"
echo "Zabbix Server:"
systemctl status zabbix-server --no-pager | grep "Active:"
echo "Nginx:"
systemctl status nginx --no-pager | grep "Active:"
echo "PHP-FPM:"
systemctl status php8.3-fpm --no-pager | grep "Active:"

echo ""
echo "--- Bağlantı Testi ---"
sudo -u zabbix PGPASSWORD=$DB_PASSWORD psql -h localhost -U $DB_USER -d $DB_NAME -c "SELECT version();" 2>/dev/null && echo "✓ Veritabanı bağlantısı başarılı!" || echo "✗ Veritabanı bağlantısı başarısız!"

echo ""
echo "--- Kurulum Sonrası Yapılacaklar ---"
echo "1. Web arayüzünü açın: http://$(hostname -I | awk '{print $1}')"
echo "2. Kurulum sihirbazını tamamlayın"
echo "3. Giriş yapın: Admin / zabbix"
echo "4. Varsayılan şifreyi değiştirin!"

#!/bin/bash
# ============================================
# Zabbix 7.0 LTS + TimescaleDB - GÜVENLİ TEMİZLİK
# PostgreSQL'deki diğer veritabanlarına dokunmaz
# ============================================

set -e

# --- RENKLER ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}=== $1 ===${NC}"; }
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }

# --- ONAY ---
echo -e "${RED}UYARI: Bu script SADECE Zabbix ile ilgili her şeyi silecektir.${NC}"
echo -e "${YELLOW}PostgreSQL'deki diğer veritabanlarına dokunulmayacaktır.${NC}"
read -p "Devam etmek için 'yes' yazın: " confirmation

if [[ "$confirmation" != "yes" ]]; then
    print_warning "Kaldırma işlemi iptal edildi."
    exit 0
fi

# --- 1. SERVİSLERİ DURDUR ---
print_status "1. Servisler Durduruluyor"
sudo systemctl stop zabbix-server zabbix-agent2 nginx php8.3-fpm 2>/dev/null || true
sudo systemctl disable zabbix-server zabbix-agent2 nginx php8.3-fpm 2>/dev/null || true
print_success "Servisler durduruldu"

# --- 2. SADECE ZABBIX PAKETLERİNİ KALDIR ---
print_status "2. Zabbix Paketleri Kaldırılıyor"

sudo apt purge -y \
    zabbix-server-pgsql \
    zabbix-frontend-php \
    zabbix-nginx-conf \
    zabbix-sql-scripts \
    zabbix-agent2 \
    timescaledb-2-postgresql-16 \
    2>/dev/null || true

sudo apt autoremove -y
sudo apt autoclean -y
print_success "Zabbix paketleri kaldırıldı"

# --- 3. SADECE ZABBIX VERİTABANINI SIL ---
print_status "3. Zabbix Veritabanı Siliniyor (PostgreSQL'e dokunulmaz)"

# Zabbix veritabanı bağlantılarını sonlandır
sudo -u postgres psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'zabbix' AND pid <> pg_backend_pid();" 2>/dev/null || true

# SADECE zabbix veritabanını ve kullanıcısını sil
sudo -u postgres psql -c "DROP DATABASE IF EXISTS zabbix;" 2>/dev/null || true
sudo -u postgres psql -c "DROP USER IF EXISTS zabbix;" 2>/dev/null || true

print_success "Zabbix veritabanı temizlendi (diğer veritabanları korundu)"

# --- 4. ZABBIX YAPILANDIRMA DOSYALARINI TEMİZLE ---
print_status "4. Zabbix Yapılandırma Dosyaları Temizleniyor"

sudo rm -rf /etc/zabbix
sudo rm -rf /usr/share/zabbix
sudo rm -rf /var/lib/zabbix
sudo rm -rf /var/log/zabbix
sudo rm -rf /var/cache/zabbix

# PHP-FPM pool dosyasını temizle (sadece Zabbix olanı)
sudo rm -f /etc/php/8.3/fpm/pool.d/zabbix-php-fpm.conf
sudo rm -f /etc/zabbix/php-fpm.conf

# Nginx konfigürasyonunu temizle (sadece Zabbix olanı)
sudo rm -f /etc/nginx/sites-enabled/zabbix
sudo rm -f /etc/nginx/conf.d/zabbix.conf
sudo rm -f /etc/nginx/sites-available/zabbix

print_success "Zabbix yapılandırma dosyaları temizlendi"

# --- 5. REPOLARI VE GPG ANAHTARLARINI KALDIR ---
print_status "5. Zabbix Repoları ve GPG Anahtarları Kaldırılıyor"

sudo rm -f /etc/apt/sources.list.d/zabbix.list
sudo rm -f /etc/apt/trusted.gpg.d/zabbix*
sudo rm -f /usr/share/keyrings/zabbix*
sudo apt update --fix-missing 2>/dev/null || true
print_success "Repolar temizlendi"

# --- 6. KALAN DOSYALARI TEMİZLE ---
print_status "6. Kalan Zabbix Dosyaları Temizleniyor"

sudo rm -rf /run/zabbix
sudo rm -rf /tmp/zabbix*
sudo rm -rf /var/tmp/zabbix*
sudo rm -rf /var/cache/apt/archives/zabbix*
sudo rm -rf /var/lib/dpkg/info/zabbix*
sudo rm -rf /usr/share/doc/zabbix-release
# Zabbix kullanıcısını sil (opsiyonel)
sudo userdel zabbix 2>/dev/null || true
sudo groupdel zabbix 2>/dev/null || true

print_success "Kalan dosyalar temizlendi"

# --- 7. SERVİSLERİ YENİDEN YÜKLE ---
print_status "7. Servisler Yeniden Yükleniyor"
sudo systemctl daemon-reload
print_success "Servisler yeniden yüklendi"

# --- 8. ÖZET ---
echo ""
echo "========================================="
echo -e "${GREEN}✓ TEMİZLİK TAMAMLANDI!${NC}"
echo "========================================="
echo ""
echo "   Kaldırılanlar:"
echo "   ✓ Zabbix Server, Agent, Web Arayüzü"
echo "   ✓ SADECE 'zabbix' veritabanı ve kullanıcısı"
echo "   ✓ Zabbix yapılandırma ve log dosyaları"
echo "   ✓ Zabbix repoları ve GPG anahtarları"
echo ""
echo "========================================="
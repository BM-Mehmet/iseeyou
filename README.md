## Açıklama

Bu script, Ubuntu 24.04 LTS üzerinde Zabbix 7.0 LTS'in otomatik kurulumunu gerçeklestirir. Kurulum aşağıdaki bileşenleri içerir:

- Zabbix Server 7.0 LTS
- PostgreSQL 16 (Veritabani)
- TimescaleDB (Zaman serisi veritabani optimizasyonu)
- Zabbix Agent 2
- Nginx (Web sunucusu)
- PHP 8.3 (Web arayuzu)

### Kurulum

Script'i aşağıdaki komutla çalıştırın:

```bash
   sudo bash iseeyou.sh
```
Değişiklik yapmadan direk kuruluma başlamak için aşağıdaki komutu kullanabilirsiniz:
```bash
bash <(curl -s https://raw.githubusercontent.com/BM-Mehmet/iseeyou/main/iseeyou.sh) 
```
NOT: Script kusursuz değildir manuel müdehale gerekebilir.

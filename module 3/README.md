# ДЕМО-ЭКЗАМЕН — Быстрая шпаргалка

## Как запустить

```bash
# Скопировать скрипты на нужный хост:
scp -P 2026 -r exam_scripts/ sshuser@<IP>:/tmp/

# На хосте:
cd /tmp/exam_scripts
chmod +x *.sh

# Запустить интерактивное меню:
./00_MENU.sh

# Или напрямую нужное задание:
./01_import_users_BR-SRV.sh
./02_ca_setup.sh hq-srv
./03_ipsec_tunnel.sh hq-rtr
```

---

## Сводная таблица заданий

| № | Задание           | Статус в PDF       | Хост(ы)                   | Скрипт                    |
|---|-------------------|--------------------|---------------------------|---------------------------|
| 1 | Импорт AD         | ✅ Работает         | BR-SRV                    | `01_import_users_BR-SRV.sh` |
| 2 | ЦС / TLS GOST     | ⚠️ Ломает nginx    | HQ-SRV, ISP, Клиент       | `02_ca_setup.sh [роль]`   |
| 3 | IPSec GRE туннель | ❌ Не работает      | HQ-RTR, BR-RTR             | `03_ipsec_tunnel.sh [роль]` |
| 4 | nftables firewall | ❓ Не проверяла    | HQ-RTR, BR-RTR             | `04_nftables_firewall.sh` |
| 5 | CUPS принт-сервер | ✅ Работает         | HQ-SRV                    | `05_cups_print_server.sh` |
| 6 | Rsyslog логи      | ✅ Работает         | HQ-SRV (сервер), остальные | `06_rsyslog.sh [роль]`    |
| 7 | Prometheus/Grafana| ✅ Работает         | HQ-SRV, BR-SRV            | `07_monitoring.sh [роль]` |
| 8 | Ansible           | ✅ Работает         | BR-SRV                    | `08_ansible.sh`           |
| 9 | Fail2ban          | ❌ Не банит         | HQ-SRV                    | `09_fail2ban.sh`          |

---

## Известные проблемы и фиксы

### Задание 2 — CA ломает nginx
- Проблема: GOST шифры не поддерживаются стандартным nginx
- Решение: убедитесь что установлен `openssl-gost-engine` и nginx собран с GOST поддержкой
- После `nginx -t` смотрите конкретную ошибку

### Задание 3 — туннель не проверяется
- После запуска скрипта: `tcpdump -i ens18 -n -p esp` на BR-RTR
- Пинг через туннель: `ping 10.5.5.1` с BR-RTR

### Задание 9 — fail2ban не банит
- Убедитесь что `/var/log/auth.log` заполняется: `tail -f /var/log/auth.log`
- SSH попытки должны идти на порт `2026`, не 22
- Проверка: `fail2ban-client set sshd unbanip <IP>` — если ошибка "not banned", значит не срабатывает
- Альтернатива backend: попробуйте `backend = auto` вместо `systemd`

---

## Полезные команды для проверки

```bash
# AD пользователи
samba-tool user list
samba-tool ou list

# IPSec
ipsec status
ipsec statusall

# nftables
nft list ruleset

# CUPS
systemctl status cups
lpstat -v

# Rsyslog
tail -f /opt/hq-rtr/hq-rtr.log
logger -p warn "test message"

# Prometheus
curl http://localhost:9090/-/healthy
curl http://localhost:9100/metrics | head

# Fail2ban
fail2ban-client status sshd
fail2ban-client set sshd unbanip <IP>
```

---

## Пароли (из документа)
| Где              | Пользователь  | Пароль      |
|------------------|---------------|-------------|
| Samba AD         | Administrator | P@ssw0rd    |
| CUPS             | root          | toor        |
| Grafana          | admin         | admin→P@ssw0rd |
| IPSec PSK        | —             | P@ssw0rd    |

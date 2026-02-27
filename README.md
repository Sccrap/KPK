# КПК — Автоматизация демо-экзамена (ALT Linux)

Полный набор bash-скриптов для автоматической настройки сетевой инфраструктуры на ALT Linux. Покрывает все три модуля демо-экзамена: от базовой настройки IP и маршрутизации до Samba AD, Docker, мониторинга и защиты.

---

## Топология сети

```
                        ┌─────────┐
                        │   ISP   │
                        │ ens19(dhcp)
                        │ ens20: 172.16.1.14/28
                        │ ens21: 172.16.2.14/28
                        └──┬───┬──┘
                           │   │
              ┌────────────┘   └────────────┐
              │                             │
        ┌─────┴─────┐                ┌──────┴─────┐
        │  HQ-RTR   │   GRE tun1    │   BR-RTR   │
        │ens19: 172.16.1.1/28 ◄──────► 172.16.2.1/28│
        │ tun1: 10.5.5.1/30         │ tun1: 10.5.5.2/30
        │                           │ens20: 192.168.1.30/27
        │ OVS bridge: hq-sw         └──────┬──────┘
        │ ├ vlan100: 192.168.0.62/26       │
        │ ├ vlan200: 192.168.0.78/28       │
        │ └ vlan999: 192.168.0.86/29  ┌────┴─────┐
        └──┬──┬──┬──┘                 │  BR-SRV  │
           │  │  │                    │192.168.1.1/27
    ┌──────┘  │  └─────┐              └──────────┘
    │         │        │
┌───┴───┐ ┌──┴───┐ ┌──┴───┐
│HQ-SRV │ │HQ-CLI│ │HQ-SW │
│.0.1/26│ │ DHCP │ │.0.81/29│
└───────┘ └──────┘ └───────┘
```

**Домен:** `au-team.irpo` · **Tunnel:** GRE + OSPF (FRR) · **VLAN:** 100 (SRV), 200 (CLI), 999 (MGMT)

---

## Структура проекта

```
KPK/
├── README.md              ← этот файл
├── module1/               ← Базовая сетевая инфраструктура
│   ├── 01_isp.sh              ISP: hostname, IP, NAT, forwarding
│   ├── 02_hq-rtr.sh           HQ-RTR: IP, VLAN(OVS), GRE, OSPF, DHCP, NAT
│   ├── 03_br-rtr.sh           BR-RTR: IP, GRE, OSPF, NAT
│   ├── 04_hq-srv.sh           HQ-SRV: IP, SSH, DNS (BIND), пользователи
│   ├── 05_hq-cli.sh           HQ-CLI: DHCP-клиент
│   ├── 06_hq-sw.sh            HQ-SW: статический IP
│   └── 07_br-srv.sh           BR-SRV: IP, SSH, пользователи
│
├── module2/               ← Службы и сервисы
│   ├── m2_01_br-srv_samba-ad.sh       Samba AD контроллер домена
│   ├── m2_02_hq-cli_domain-join.sh    Ввод клиента в домен
│   ├── m2_03_br-srv_samba-users.sh    Пользователи/группы AD
│   ├── m2_04_hq-srv_raid-nfs.sh       RAID0 + NFS-сервер
│   ├── m2_05_hq-cli_nfs-client.sh     NFS-клиент (автомонтирование)
│   ├── m2_06_isp_ntp-server.sh        NTP-сервер (chrony)
│   ├── m2_07_ntp-client.sh            NTP-клиент (универсальный)
│   ├── m2_08_br-srv_ansible.sh        Ansible: ключи, инвентарь
│   ├── m2_09_br-srv_docker.sh         Docker Compose: MariaDB + site
│   ├── m2_10_hq-srv_web.sh            Web: MariaDB + Apache + PHP
│   ├── m2_11_hq-rtr_port-forward.sh   DNAT на HQ-RTR (nftables)
│   ├── m2_12_br-rtr_port-forward.sh   DNAT на BR-RTR (nftables)
│   ├── m2_13_hq-rtr_nginx-proxy.sh    Nginx reverse proxy
│   ├── m2_14_isp_nginx-auth.sh        Nginx htpasswd аутентификация
│   ├── m2_15_hq-cli_yandex.sh         Яндекс Браузер
│   └── m2_16_hq-cli_sudo-hq.sh        Sudo для доменной группы hq
│
└── module3/               ← Безопасность и мониторинг
    ├── 00_MENU.sh                 Интерактивное меню запуска
    ├── 01_import_users_BR-SRV.sh  Импорт AD-пользователей из CSV
    ├── 02_ca_setup.sh             Центр сертификации (GOST TLS)
    ├── 03_ipsec_tunnel.sh         IPSec/GRE туннель (StrongSwan)
    ├── 04_nftables_firewall.sh    Межсетевой экран nftables
    ├── 05_cups_print_server.sh    Принт-сервер CUPS
    ├── 06_rsyslog.sh              Централизованное логирование
    ├── 07_monitoring.sh           Prometheus + Grafana + node_exporter
    ├── 08_ansible.sh              Ansible playbook инвентаризации
    └── 09_fail2ban.sh             Fail2ban защита SSH
```

---

## Быстрый старт

```bash
# 1. Скопировать на нужное устройство
scp -r module1/ root@<IP>:/root/scripts/

# 2. На устройстве
cd /root/scripts
chmod +x *.sh

# 3. Запустить нужный скрипт
bash 01_isp.sh
```

Для Модуля 3 есть интерактивное меню:
```bash
cd module3/
bash 00_MENU.sh
```

---

## Порядок выполнения

### Модуль 1 — Сетевая инфраструктура

| Шаг | Устройство | Скрипт | Примечание |
|-----|-----------|--------|------------|
| 1 | ISP | `01_isp.sh` | Первым — от него зависят остальные |
| 2 | HQ-RTR | `02_hq-rtr.sh` | VLAN, GRE, OSPF, DHCP |
| 3 | BR-RTR | `03_br-rtr.sh` | GRE, OSPF |
| 4 | HQ-SRV | `04_hq-srv.sh` | DNS BIND, SSH |
| 5 | BR-SRV | `07_br-srv.sh` | SSH |
| 6 | HQ-CLI | `05_hq-cli.sh` | DHCP-клиент |
| 7 | HQ-SW | `06_hq-sw.sh` | Статический IP |

> После шагов 2-3 может потребоваться `reboot` на обоих роутерах для поднятия GRE+OSPF.

### Модуль 2 — Службы

| Шаг | Устройство | Скрипт | Зависимость |
|-----|-----------|--------|-------------|
| 1 | BR-SRV | `m2_01_...samba-ad.sh` | Требует reboot после |
| 2 | HQ-CLI | `m2_02_...domain-join.sh` | После reboot BR-SRV |
| 3 | BR-SRV | `m2_03_...samba-users.sh` | После join |
| 4 | HQ-SRV | `m2_04_...raid-nfs.sh` | Диски sdb/sdc должны быть подключены |
| 5 | HQ-CLI | `m2_05_...nfs-client.sh` | После NFS-сервера |
| 6 | ISP | `m2_06_...ntp-server.sh` | — |
| 7 | ВСЕ* | `m2_07_ntp-client.sh` | После NTP-сервера |
| 8 | BR-SRV | `m2_08_...ansible.sh` | Нужен sshpass |
| 9 | BR-SRV | `m2_09_...docker.sh` | Additional.iso в CD-ROM |
| 10 | HQ-SRV | `m2_10_...web.sh` | Additional.iso в CD-ROM |
| 11 | HQ-RTR | `m2_11_...port-forward.sh` | После M1 NAT |
| 12 | BR-RTR | `m2_12_...port-forward.sh` | После M1 NAT |
| 13 | HQ-RTR | `m2_13_...nginx-proxy.sh` | — |
| 14 | ISP | `m2_14_...nginx-auth.sh` | — |
| 15 | HQ-CLI | `m2_15_...yandex.sh` | Нужен интернет |
| 16 | HQ-CLI | `m2_16_...sudo-hq.sh` | После domain join |

### Модуль 3 — Безопасность и мониторинг

| # | Задание | Устройство | Скрипт | Статус |
|---|---------|-----------|--------|--------|
| 1 | Импорт AD из CSV | BR-SRV | `01_import_users_BR-SRV.sh` | ✅ |
| 2 | ЦС GOST TLS | HQ-SRV / ISP / CLI | `02_ca_setup.sh [роль]` | ⚠️ |
| 3 | IPSec GRE | HQ-RTR / BR-RTR | `03_ipsec_tunnel.sh [роль]` | ⚠️ |
| 4 | Firewall nftables | HQ-RTR / BR-RTR | `04_nftables_firewall.sh` | ✅ |
| 5 | CUPS принт-сервер | HQ-SRV | `05_cups_print_server.sh` | ✅ |
| 6 | Rsyslog | HQ-SRV + клиенты | `06_rsyslog.sh [роль]` | ✅ |
| 7 | Prometheus/Grafana | HQ-SRV / BR-SRV | `07_monitoring.sh [роль]` | ✅ |
| 8 | Ansible playbook | BR-SRV | `08_ansible.sh` | ✅ |
| 9 | Fail2ban | HQ-SRV | `09_fail2ban.sh` | ⚠️ |

---

## Результаты анализа и найденные проблемы

### Критические проблемы

**1. Конфликт SSH-портов между модулями (M2 vs M3)**

В Модуле 1/2 SSH-порт серверов настроен как `2024`, а в `module3/08_ansible.sh` и `module3/09_fail2ban.sh` используется порт `2026`. Это приведёт к ошибкам подключения Ansible и некорректной работе Fail2ban.

Затронутые файлы:
- `module1/04_hq-srv.sh` → `SSH_PORT="2024"`
- `module1/07_br-srv.sh` → `SSH_PORT="2024"`
- `module3/08_ansible.sh` → `ansible_port=2026`
- `module3/09_fail2ban.sh` → `port=2026`

> **Решение:** Привести к единому порту. Если задание требует 2024 — исправить M3, если 2026 — исправить M1.

**2. M3 nftables firewall перезаписывает NAT (flush ruleset)**

Скрипт `04_nftables_firewall.sh` содержит `flush ruleset`, что удалит все правила NAT (masquerade, DNAT), настроенные в Модулях 1-2. После его запуска ISP перестанет NATить, DNAT на роутерах сломается.

> **Решение:** Запускать `04_nftables_firewall.sh` **до** скриптов DNAT из M2, либо добавить таблицу nat в конфигурацию firewall.

**3. M3 Ansible inventory содержит захардкоженные IP/пользователей**

В `module3/08_ansible.sh` IP-адрес HQ-CLI `192.168.0.2` не соответствует DHCP-пулу из M1 (`192.168.0.65-75`), а пользователь `kmw` нигде не создаётся.

> **Решение:** Использовать `192.168.0.65` и пользователя `user` (или создать нужного).

### Некритичные проблемы

**4. Отсутствие `set -e` в скриптах M3**

Скрипты M3 (`00_MENU.sh`, `01_import_users_BR-SRV.sh`, `04_nftables_firewall.sh` и другие) не содержат `set -e`, из-за чего ошибки могут быть пропущены молча.

**5. M2 RAID скрипт: sfdisk двойной вызов**

В `m2_04_hq-srv_raid-nfs.sh` sfdisk вызывается дважды (сначала `label: gpt`, потом `,,L`). На некоторых версиях ALT Linux первый вызов может удалить второй. Безопаснее объединить:
```bash
echo -e "label: gpt\n,,L" | sfdisk "$disk" --force
```

**6. M2 OVS VLAN: IP восстанавливается через .bashrc**

Вместо systemd unit VLAN IP-адреса восстанавливаются через `bash /root/ip.sh` в `.bashrc`. Это работает только при интерактивном логине root. Для надёжности лучше использовать systemd oneshot service.

**7. M2 Samba AD: DNS backend = SAMBA_INTERNAL**

Используется встроенный DNS Samba, который конфликтует с BIND на HQ-SRV если resolv.conf клиента указывает на оба. Нужно следить чтобы HQ-CLI для AD-авторизации указывал на BR-SRV (192.168.1.1), а для общего DNS — на HQ-SRV.

**8. M3 fail2ban: backend = systemd, но logpath = /var/log/auth.log**

Если `backend = systemd`, logpath игнорируется (fail2ban читает journald). Если нужен файл — поставить `backend = auto`.

---

## Учётные данные

| Сервис | Пользователь | Пароль | Где используется |
|--------|-------------|--------|-----------------|
| Серверы (SSH) | `sshuser` | `P@ssw0rd` | HQ-SRV, BR-SRV |
| Маршрутизаторы | `net_admin` | `P@$$word` | HQ-RTR, BR-RTR |
| Samba AD | `Administrator` | `P@ssw0rd` | BR-SRV (DC) |
| MariaDB (web) | `webc` / `root` | `P@ssw0rd` | HQ-SRV |
| Docker DB | `test` / `root` | `P@ssw0rd` | BR-SRV |
| Grafana | `admin` | `admin` → `P@ssw0rd` | HQ-SRV:3000 |
| Nginx htpasswd | `WEB` | `P@ssw0rd` | ISP |
| OSPF auth | — | `P@ssw0rd` | HQ-RTR ↔ BR-RTR |
| IPSec PSK | — | `P@ssw0rd` | HQ-RTR ↔ BR-RTR |

---

## Полезные команды для проверки

```bash
# === Сеть ===
ip -c -br a                    # Интерфейсы
ip -c -br r                    # Маршруты
ovs-vsctl show                 # OVS (HQ-RTR)
nft list ruleset               # Правила файрвола
traceroute 192.168.0.1         # Трассировка

# === OSPF ===
vtysh -c "show ip route ospf"
vtysh -c "show ip ospf neighbor"

# === DNS ===
nslookup hq-srv.au-team.irpo 192.168.0.1
named-checkconf -z

# === Samba AD ===
samba-tool user list
samba-tool domain info 127.0.0.1

# === NFS ===
exportfs -v                    # Сервер
df -h /mnt/nfs                 # Клиент

# === Docker ===
docker ps
docker compose -f web.yaml logs

# === Мониторинг ===
curl http://localhost:9090/-/healthy    # Prometheus
curl http://localhost:9100/metrics      # node_exporter

# === Fail2ban ===
fail2ban-client status sshd

# === Rsyslog ===
logger -p warn "test from $(hostname)"
tail -f /opt/hq-rtr/hq-rtr.log
```

---

## Требования

- **ОС:** ALT Linux (Сервер / Рабочая станция)
- **Запуск:** от root (`su -` или `sudo bash`)
- **Перед запуском:** проверить имена интерфейсов (`ip -c a`) и при необходимости изменить переменные в начале скриптов (секция `ПЕРЕМЕННЫЕ`)
- **Additional.iso:** Для Docker и Web-сервера нужен образ Additional.iso, подключённый как CD-ROM (`/dev/sr0`)
- **Диски:** Для RAID0 нужны два дополнительных диска (sdb, sdc)
# ДЭМ Экзамен — Скрипты автоматизации

## Структура

```
test/
├── README.md
├── module1/
│   ├── m1_isp.sh       — Настройка ISP
│   ├── m1_hq-rtr.sh    — Настройка HQ-RTR
│   ├── m1_br-rtr.sh    — Настройка BR-RTR
│   ├── m1_hq-srv.sh    — Настройка HQ-SRV
│   ├── m1_br-srv.sh    — Настройка BR-SRV
│   └── m1_hq-cli.sh    — Настройка HQ-CLI
├── module2/
│   ├── m2_isp.sh       — Chrony + Nginx на ISP (задания 1, 4, 5)
│   ├── m2_hq-rtr.sh    — NAT/nftables HQ-RTR (задание 7)
│   ├── m2_br-rtr.sh    — NAT/nftables BR-RTR (задание 7)
│   ├── m2_hq-srv.sh    — Samba-клиент, RAID, NFS, Apache (задания 2, 6, 9)
│   ├── m2_br-srv.sh    — Samba AD DC, Ansible, Docker (задания 2, 3, 8)
│   └── m2_hq-cli.sh    — Клиентские настройки (задания 2, 4, 5)
└── module3/
    ├── m3_hq-srv.sh    — CA, CUPS, Rsyslog, Prometheus, Fail2ban (задания 2,5,6,7,9)
    ├── m3_br-srv.sh    — Импорт пользователей, Ansible 2.0, Мониторинг (задания 1,8,7)
    ├── m3_hq-rtr.sh    — IPsec, Firewall, Rsyslog-клиент (задания 3,4,6)
    └── m3_br-rtr.sh    — IPsec, Firewall, Rsyslog-клиент (задания 3,4,6)
```

## Топология сети

```
              ISP (172.16.1.14/28 | 172.16.2.14/28)
             /                              \
    HQ-RTR (172.16.1.1/28)         BR-RTR (172.16.2.1/28)
    ├── vlan10: 192.168.1.0/27      └── 192.168.4.0/28
    ├── vlan20: 192.168.2.0/28           └── BR-SRV (192.168.4.2)
    ├── vlan99: 192.168.3.0/29
    ├── HQ-SRV (192.168.1.2)
    └── HQ-CLI (192.168.2.x — DHCP)
```

## Пароли

| Пользователь       | Пароль      |
|--------------------|-------------|
| Administrator (AD) | P@ssw0rd    |
| net_admin          | P@ssw0rd    |
| remote_user        | Pa$$word    |
| WEBc (nginx)       | P@ssw0rd    |
| root MariaDB       | P@ssw0rd    |
| webc (MariaDB)     | P@ssw0rd    |

## Порядок выполнения

1. Сначала выполни **module1** — базовая сетевая настройка всех устройств
2. Затем **module2** — сервисы (Samba, Ansible, Docker, Nginx и др.)
3. Затем **module3** — дополнительные сервисы (CA, мониторинг, логирование, fail2ban)

> ⚠️ Docker (модуль 2, задание 8) **ломает Samba** — выполняй в последнюю очередь внутри модуля 2.
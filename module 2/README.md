# Автоматизация Модуль 2 — ALT Linux

## Структура скриптов

| # | Скрипт | Устройство | Описание |
|---|--------|-----------|----------|
| 1 | `m2_01_br-srv_samba-ad.sh` | BR-SRV | Samba AD контроллер домена |
| 2 | `m2_02_hq-cli_domain-join.sh` | HQ-CLI | Ввод в домен AD, resolv.conf |
| 3 | `m2_03_br-srv_samba-users.sh` | BR-SRV | Создание пользователей/групп AD через samba-tool |
| 4 | `m2_04_hq-srv_raid-nfs.sh` | HQ-SRV | RAID0, файловое хранилище, NFS-сервер |
| 5 | `m2_05_hq-cli_nfs-client.sh` | HQ-CLI | NFS-клиент, автомонтирование |
| 6 | `m2_06_isp_ntp-server.sh` | ISP | NTP-сервер (chrony) |
| 7 | `m2_07_ntp-client.sh` | HQ-RTR/BR-RTR/HQ-SRV/BR-SRV/HQ-CLI | NTP-клиент |
| 8 | `m2_08_br-srv_ansible.sh` | BR-SRV | Ansible: ключи, инвентарь, конфиг |
| 9 | `m2_09_br-srv_docker.sh` | BR-SRV | Docker: MariaDB + site (docker compose) |
| 10 | `m2_10_hq-srv_web.sh` | HQ-SRV | Web-сервер: MariaDB + Apache + PHP |
| 11 | `m2_11_hq-rtr_port-forward.sh` | HQ-RTR | Статическая трансляция портов (DNAT) |
| 12 | `m2_12_br-rtr_port-forward.sh` | BR-RTR | Статическая трансляция портов (DNAT) |
| 13 | `m2_13_hq-rtr_nginx-proxy.sh` | HQ-RTR | Nginx reverse proxy |
| 14 | `m2_14_isp_nginx-auth.sh` | ISP | Nginx web-based аутентификация |
| 15 | `m2_15_hq-cli_yandex.sh` | HQ-CLI | Установка Яндекс Браузера |

## Порядок выполнения

1. Samba AD на BR-SRV → ввод HQ-CLI в домен → создание пользователей
2. RAID + NFS на HQ-SRV → NFS-клиент на HQ-CLI
3. NTP на ISP → NTP-клиенты на остальных
4. Ansible на BR-SRV
5. Docker на BR-SRV
6. Web на HQ-SRV
7. Port forwarding на роутерах
8. Nginx proxy на HQ-RTR, auth на ISP
9. Яндекс Браузер на HQ-CLI

## Важно

- Все скрипты запускать от root: `chmod +x <script>.sh && bash <script>.sh`
- Переменные в начале каждого скрипта — проверить и при необходимости изменить
- Samba AD требует перезагрузки BR-SRV после настройки
- Docker: образы загружаются с Additional.iso (`/dev/sr0`)

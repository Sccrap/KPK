#!/bin/bash
# ============================================================
# ЗАДАНИЕ 4: Межсетевой экран nftables
# Выполняется на: HQ-RTR и BR-RTR (одинаковые правила)
# ============================================================

echo "=== ЗАДАНИЕ 4: Настройка nftables ==="

NFTABLES_CONF="/etc/nftables/nftables.nft"

echo "[1/2] Создание конфигурации nftables..."

# Бэкап
cp "${NFTABLES_CONF}" "${NFTABLES_CONF}.bak" 2>/dev/null || true

cat > "${NFTABLES_CONF}" << 'NFTCONF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {

    chain input {
        type filter hook input priority 0; policy drop;
        log prefix "Dropped Input: " level debug

        # Разрешаем loopback
        iif lo accept

        # Разрешаем установленные соединения
        ct state established, related accept

        # TCP порты: SSH(22,2026), Syslog(514), DNS(53), HTTP(80),
        #           HTTPS(443), Samba(445,139,88,389), NFS(2049),
        #           CUPS(631), Custom(3015,8080)
        tcp dport { 22, 514, 53, 80, 443, 3015, 445, 139, 88, 2026, 8080, 2049, 389, 631 } accept

        # UDP порты: DNS(53), NTP(123), IKE(500,4500), Kerberos(88),
        #            NetBIOS(137), NFS(2049), CUPS(631)
        udp dport { 53, 123, 500, 4500, 88, 137, 8080, 2049, 631 } accept

        # Протоколы
        ip protocol icmp accept
        ip protocol esp accept
        ip protocol gre accept
        ip protocol ospf accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        log prefix "Dropped forward: " level debug

        iif lo accept
        ct state established, related accept

        tcp dport { 22, 514, 53, 80, 443, 3015, 445, 139, 88, 2026, 8080, 2049, 389, 631 } accept
        udp dport { 53, 123, 500, 4500, 88, 137, 8080, 2049, 631 } accept

        ip protocol icmp accept
        ip protocol esp accept
        ip protocol gre accept
        ip protocol ospf accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
NFTCONF

echo "[OK] Конфиг nftables записан"

echo "[2/2] Применение правил..."
nft -f "${NFTABLES_CONF}" && echo "[OK] Правила применены" || echo "[ERR] Ошибка в правилах nftables!"
systemctl restart nftables && echo "[OK] nftables перезапущен"
systemctl enable nftables

echo ""
echo "=== ПРОВЕРКА ==="
nft list ruleset | head -50
echo ""
echo "[*] Полная таблица: nft list ruleset"

#!/bin/bash
# ============================================================
# MODULE 1 — HQ-RTR
# Hostname, IP, NAT, VLAN (OVS), DHCP, пользователь net_admin
# ============================================================
set -e

echo "[*] === HQ-RTR: Начало настройки ==="

# --- Hostname ---
hostnamectl set-hostname hq-rtr

# --- IP Forwarding ---
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf || \
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf

# --- DNS и IP-адреса ---
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
echo '172.16.1.1/28'   > /etc/net/ifaces/ens19/ipv4address
echo '192.168.1.1/27'  > /etc/net/ifaces/ens20/ipv4address
echo '192.168.2.1/28'  > /etc/net/ifaces/ens21/ipv4address
echo '192.168.3.1/29'  > /etc/net/ifaces/ens22/ipv4address
echo 'default via 172.16.1.14' > /etc/net/ifaces/ens19/ipv4route
systemctl restart network

echo "[*] Проверяем интернет..."
ping -c 2 8.8.8.8 || echo "[!] Интернет недоступен — проверь ISP"

# --- Установка пакетов ---
apt-get update -y
apt-get install -y nano nftables sudo dhcp-server NetworkManager-ovs frr

# --- NAT ---
cat >> /etc/nftables/nftables.nft << 'EOF'

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "ens19" masquerade
  }
}
EOF
systemctl enable --now nftables
systemctl restart nftables

# --- Пользователь net_admin ---
echo "[*] Создаём пользователя net_admin..."
if ! id net_admin &>/dev/null; then
  adduser --disabled-password --gecos "" net_admin
fi
echo "net_admin:P@ssw0rd" | chpasswd
usermod -aG wheel net_admin
echo 'net_admin ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers

# --- VLAN через OpenVSwitch ---
echo "[*] Настраиваем VLAN (OpenVSwitch)..."
systemctl enable --now openvswitch

ovs-vsctl add-br hq-sw

ovs-vsctl add-port hq-sw ens20 tag=10
ovs-vsctl add-port hq-sw ens21 tag=20
ovs-vsctl add-port hq-sw ens22 tag=99

ovs-vsctl add-port hq-sw vlan10 tag=10 -- set interface vlan10 type=internal
ovs-vsctl add-port hq-sw vlan20 tag=20 -- set interface vlan20 type=internal
ovs-vsctl add-port hq-sw vlan99 tag=99 -- set interface vlan99 type=internal

systemctl restart openvswitch

# Удаляем старые IP с физических портов
rm -f /etc/net/ifaces/ens20/ipv4address
rm -f /etc/net/ifaces/ens21/ipv4address
rm -f /etc/net/ifaces/ens22/ipv4address

ip link set hq-sw up

# --- Скрипт VLAN IP (vlan.sh) ---
echo "[*] Создаём vlan.sh..."
cat > /root/vlan.sh << 'EOF'
#!/bin/bash
ip a add 192.168.1.1/27 dev vlan10 2>/dev/null || true
ip a add 192.168.2.1/28 dev vlan20 2>/dev/null || true
ip a add 192.168.3.1/29 dev vlan99 2>/dev/null || true
systemctl restart dhcpd 2>/dev/null || true
EOF
chmod +x /root/vlan.sh

# Добавляем в ~/.bashrc автозапуск
grep -q 'vlan.sh' /root/.bashrc || echo 'bash /root/vlan.sh' >> /root/.bashrc

# Применяем сразу
bash /root/vlan.sh

# --- DHCP ---
echo "[*] Настраиваем DHCP..."
cp /etc/dhcp/dhcpd.conf.example /etc/dhcp/dhcpd.conf

cat > /etc/dhcp/dhcpd.conf << 'EOF'
# A slightly different configuration for an internal subnet.
subnet 192.168.2.0 netmask 255.255.255.240 {
  range 192.168.2.2 192.168.2.14;
  option routers 192.168.2.1;
  option domain-name-servers 192.168.1.2;
  option domain-name "aks42.aks";
  default-lease-time 600;
  max-lease-time 7200;
}
EOF

echo 'DHCPDARGS=vlan20' > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd
systemctl status dhcpd --no-pager

echo "[+] === HQ-RTR: Настройка завершена ==="
echo "[!] Перезагрузи устройство командой: reboot"

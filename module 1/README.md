# Module 1 — Network Infrastructure (ALT Linux)

Scripts automate the complex parts of each device setup. **Basic IP configuration
must be done manually first** so that files can be transferred and scripts run.

---

## Step 0 — Manual IP Configuration (do this before running any script)

Every device needs a reachable IP before you can copy scripts to it.
Use the templates below directly in the console of each VM.

### Template — static interface (ALT Linux)

```bash
IFACE="ens19"
IP="x.x.x.x/xx"
GW="x.x.x.x"          # omit the next line if no gateway needed

mkdir -p /etc/net/ifaces/$IFACE

cat > /etc/net/ifaces/$IFACE/options <<EOF
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

echo "$IP"           > /etc/net/ifaces/$IFACE/ipv4address
echo "default via $GW" > /etc/net/ifaces/$IFACE/ipv4route   # omit if no GW

systemctl restart network
ip -br a
```

### Template — DHCP client interface (HQ-CLI)

```bash
IFACE="ens19"
mkdir -p /etc/net/ifaces/$IFACE

cat > /etc/net/ifaces/$IFACE/options <<EOF
BOOTPROTO=dhcp
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=dhcp
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

rm -f /etc/net/ifaces/$IFACE/ipv4address \
      /etc/net/ifaces/$IFACE/ipv4route

systemctl restart network
ip -br a
```

### Per-device address table

| Device  | Interface | Address / Mode    | Gateway       | Notes                          |
|---------|-----------|-------------------|---------------|--------------------------------|
| ISP     | ens19     | DHCP (internet)   | —             | pre-configured, do not touch   |
| ISP     | ens20     | 172.16.1.14/28    | —             | towards HQ-RTR                 |
| ISP     | ens21     | 172.16.2.14/28    | —             | towards BR-RTR                 |
| HQ-RTR  | ens19     | 172.16.1.1/28     | 172.16.1.14   | WAN (towards ISP)              |
| BR-RTR  | ens19     | 172.16.2.1/28     | 172.16.2.14   | WAN (towards ISP)              |
| BR-RTR  | ens20     | 192.168.1.30/27   | —             | LAN (towards BR-SRV)           |
| HQ-SRV  | ens19     | 192.168.0.1/26    | 192.168.0.62  | gateway = HQ-RTR vlan100       |
| HQ-CLI  | ens19     | **DHCP**          | 192.168.0.78  | IP from HQ-RTR DHCP (vlan200)  |
| HQ-SW   | ens19     | 192.168.0.81/29   | 192.168.0.86  | gateway = HQ-RTR vlan999       |
| BR-SRV  | ens19     | 192.168.1.1/27    | 192.168.1.30  | gateway = BR-RTR LAN           |

> **HQ-CLI** cannot get a DHCP address until HQ-RTR is fully configured (script `02`).
> Configure its interface type as DHCP (template above) and restart network after HQ-RTR is done.

### DNS resolver — set after IP is up

On **HQ-SRV** (points to itself):

```bash
cat > /etc/resolv.conf <<EOF
search au-team.irpo
nameserver 192.168.0.1
nameserver 77.88.8.7
EOF
```

On **BR-SRV** (points to HQ-SRV):

```bash
cat > /etc/resolv.conf <<EOF
search au-team.irpo
nameserver 192.168.0.1
EOF
```

---

## Scripts overview

| Script         | Device | What the script configures                                                    |
|----------------|--------|-------------------------------------------------------------------------------|
| `01_isp.sh`    | ISP    | Hostname, IP forwarding, NAT (nftables)                                       |
| `02_hq-rtr.sh` | HQ-RTR | Hostname, forwarding, NAT, VLAN (OVS), GRE tunnel, OSPF, DHCP server, user    |
| `03_br-rtr.sh` | BR-RTR | Hostname, forwarding, NAT, GRE tunnel, OSPF, user                             |
| `04_hq-srv.sh` | HQ-SRV | Hostname, user, SSH (port 2024), DNS/BIND, timezone                           |
| `05_hq-cli.sh` | HQ-CLI | Hostname, timezone                                                            |
| `06_hq-sw.sh`  | HQ-SW  | Hostname, timezone                                                            |
| `07_br-srv.sh` | BR-SRV | Hostname, user, SSH (port 2024), timezone                                     |

---

## Execution order

```text
[Manual]  Configure IPs on all devices (table above)
   │
   ▼
[01] ISP        — NAT, forwarding
   │
   ▼
[02] HQ-RTR     — VLAN, DHCP, GRE, OSPF
[03] BR-RTR     — GRE, OSPF            (parallel with HQ-RTR)
   │
   ▼  reboot both routers if GRE/OSPF does not come up
   │
   ▼
[04] HQ-SRV     — DNS, SSH
[07] BR-SRV     — SSH                  (parallel with HQ-SRV)
   │
   ▼
[05] HQ-CLI     — hostname, timezone   (after HQ-RTR DHCP is ready)
[06] HQ-SW      — hostname, timezone   (parallel with HQ-CLI)
```

---

## Running a script

```bash
# From your workstation — copy the script
scp 02_hq-rtr.sh root@172.16.1.1:/root/

# On the target device
bash /root/02_hq-rtr.sh
```

Check interface names before running (`ip -c a`) and adjust the variables
at the top of each script if needed.

---

## Credentials

| Account        | Username    | Password   | Device              |
|----------------|-------------|------------|---------------------|
| SSH users      | `sshuser`   | `P@ssw0rd` | HQ-SRV, BR-SRV      |
| Router admins  | `net_admin` | `P@$$word` | HQ-RTR, BR-RTR      |
| OSPF auth key  | —           | `P@ssw0rd` | HQ-RTR ↔ BR-RTR     |

---

## Verification commands

```bash
ip -c -br a                          # interface addresses
ip -c -br r                          # routing table
ovs-vsctl show                       # OVS bridge (HQ-RTR)
nft list ruleset                     # nftables rules
vtysh -c "show ip ospf neighbor"     # OSPF neighbours
vtysh -c "show ip route ospf"        # OSPF routes
systemctl status nftables frr dhcpd bind sshd
nslookup hq-srv.au-team.irpo 192.168.0.1
```

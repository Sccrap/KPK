#!/bin/bash
# ============================================================
# MODULE 2 — HQ-CLI
# Task 2: Join Samba Active Directory domain AU-TEAM.IRPO
# Task 4: Nginx access test (web.au-team.irpo via browser)
# Task 5: Install Yandex Browser
# PDF ref: Второй.pdf tasks 2, 4, 5; Второй.pdf page 2 (Samba client)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 2 — HQ-CLI"
echo "[*] ========================================"

# ============================================================
# TASK 2: SAMBA — Domain join (client side)
# ============================================================
echo ""
echo "[*] [Task 2] Joining Active Directory domain AU-TEAM.IRPO..."

# Per PDF: set DNS to BR-SRV (192.168.4.2) — Samba DC
cat > /etc/resolv.conf << 'EOF'
nameserver 192.168.4.2
EOF
echo "[+] DNS set to BR-SRV (Samba DC): 192.168.4.2"

# Install required packages
apt-get install -y samba-common-bin krb5-workstation libpam-winbind libnss-winbind 2>/dev/null || \
  apt-get install -y samba-common krb5-workstation

# Test DC connectivity
echo "[*] Testing connectivity to BR-SRV (DC)..."
if ping -c 2 -W 3 192.168.4.2 &>/dev/null; then
  echo "[+] BR-SRV reachable"
else
  echo "[!] BR-SRV not reachable — check BR-RTR routing"
fi

echo ""
echo "=========================================================="
echo "[!] MANUAL STEP REQUIRED — Domain join via GUI:"
echo ""
echo "    1. Open: System Control Center"
echo "    2. Go to: Authentication section"
echo "    3. Select: Active Directory Domain"
echo "    4. Fill in:"
echo "       Domain:      au-team-irpo"
echo "       Workgroup:   au-team"
echo "       Computer:    hq-cli"
echo "    5. Click: Apply"
echo "    6. Enter admin password: P@ssw0rd"
echo "=========================================================="
echo ""
echo "[*] After GUI join, run kinit to verify Kerberos ticket..."
echo "[*] Run manually: kinit Administrator@AU-TEAM.IRPO"
echo "    Password: P@ssw0rd"
echo ""

# After domain join — add sudo rules for domain group
# Per PDF: allow hq group limited sudo (cat, grep, id)
if ! grep -q 'au-team' /etc/sudoers 2>/dev/null; then
  echo '%au-team\\hq ALL=(ALL) NOPASSWD:/bin/cat,/bin/grep,/bin/id' >> /etc/sudoers
  echo "[+] Domain group sudo rule added to /etc/sudoers"
fi

# ============================================================
# TASK 4: TEST NGINX ACCESS (web.au-team.irpo)
# ============================================================
echo ""
echo "[*] [Task 4] Nginx access via browser:"
echo "    URL:      http://web.au-team.irpo"
echo "    Username: WEBc"
echo "    Password: P@ssw0rd"
echo ""
echo "[!] Make sure /etc/hosts or DNS resolves web.au-team.irpo to ISP IP"
echo "    If DNS not set up yet, add manually to /etc/hosts:"
echo "    echo '<ISP-IP> web.au-team.irpo' >> /etc/hosts"

# ============================================================
# TASK 5: YANDEX BROWSER
# ============================================================
echo ""
echo "[*] [Task 5] Installing Yandex Browser..."
if apt-get install -y yandex-browser-stable 2>/dev/null || \
   apt-get install -y yandex-browser-y 2>/dev/null; then
  echo "[+] Yandex Browser installed"
  echo "[!] Add to desktop:"
  echo "    Menu -> All Programs -> Internet -> Yandex Browser"
  echo "    Right-click -> Add to Desktop"
else
  echo "[!] Yandex Browser package not found in repositories"
  echo "    Download manually from https://browser.yandex.ru/"
fi

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    DNS (BR-SRV): $(cat /etc/resolv.conf | grep nameserver)"
echo "    Domain test:  run 'kinit Administrator@AU-TEAM.IRPO'"
echo "    SSH tests:"
echo "      ssh remote_user@192.168.1.2 -p 2042  (HQ-SRV)"
echo "      ssh remote_user@192.168.4.2 -p 2042  (BR-SRV)"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-CLI MODULE 2 — COMPLETE"
echo "[!]  Complete the GUI domain join manually"
echo "[+] ========================================"

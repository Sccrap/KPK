#!/bin/bash
###############################################################################
# 05_hq-cli.sh — HQ-CLI configuration (ALT Linux)
# Module 1: hostname · timezone
#
# PRE-REQUISITE (manual, before running this script):
#   ens19 — DHCP client (gets IP from HQ-RTR DHCP, pool 192.168.0.65-75)
#   HQ-RTR must already be configured and running (script 02_hq-rtr.sh)
#   See: module 1/README.md → "Step 0 — Manual IP Configuration"
###############################################################################
set -e

HOSTNAME="hq-cli.au-team.irpo"

echo "=== [1/2] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"
echo "  Hostname: $HOSTNAME"

echo "=== [2/2] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
ip -c -br a
echo "---"
ip -c -br r
echo ""
echo "=== HQ-CLI configured ==="

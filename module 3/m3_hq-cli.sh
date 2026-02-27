#!/bin/bash
###############################################################################
# m3_hq-cli.sh — HQ-CLI configuration (Module 3, ALT Linux)
# Tasks: Add CA certificate to system trust store
#
# PRE-REQUISITE: NFS share /mnt/nfs must be mounted (done in m2_hq-cli.sh)
#                m3_hq-srv.sh must have run first to generate /raid/nfs/ca.crt
###############################################################################
set -e

# =============================================================================
echo "=== [1/1] Adding CA certificate to trust store ==="

if [ ! -f /mnt/nfs/ca.crt ]; then
    echo "  ERROR: /mnt/nfs/ca.crt not found!"
    echo "  Check NFS mount: df -h /mnt/nfs"
    echo "  Check NFS server: systemctl status nfs on HQ-SRV"
    exit 1
fi

cp /mnt/nfs/ca.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust
echo "  CA certificate added to system trust store"

mkdir -p /etc/nginx/ssl/private
echo "  nginx/ssl directories created"

echo ""
echo "=== Verification ==="
echo "Trust store updated."
echo "Test:"
echo "  curl https://web.au-team.irpo"
echo "  curl https://docker.au-team.irpo"
echo ""
echo "=== HQ-CLI (Module 3) configured ==="

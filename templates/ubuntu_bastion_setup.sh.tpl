#!/usr/bin/env bash
# Copyright IBM Corp. 2024, 2026
# SPDX-License-Identifier: MPL-2.0
#
# Setup for the Ubuntu bastion: XFCE desktop, xrdp and Google Chrome, plus a
# hosts entry so the browser can resolve the TFE FQDN.
# Output is appended to /var/log/ubuntu-bastion-setup.log.
#
# Safe to run more than once: every step either checks its state first or can
# be repeated, so if a run fails you can simply run it again.

set -euo pipefail
exec > >(tee -a /var/log/ubuntu-bastion-setup.log) 2>&1

trap 'echo "[bastion] FAILED near line $LINENO. This script is safe to re-run."' ERR

export DEBIAN_FRONTEND=noninteractive
APT_OPTS="-o DPkg::Lock::Timeout=600"

echo "[bastion] ===== Setup started $(date -u +%Y-%m-%dT%H:%M:%SZ) ====="

# Run a command up to 3 times, to ride out transient network or mirror errors.
retry() {
  local attempt=1
  until "$@"; do
    if [ "$attempt" -ge 3 ]; then
      echo "[bastion] Command failed after $attempt attempts: $*"
      return 1
    fi
    echo "[bastion] Attempt $attempt failed, retrying in 10s: $*"
    attempt=$((attempt + 1))
    sleep 10
  done
}

echo "[bastion] Removing internal apt repositories that need credentials."
find /etc/apt/sources.list.d/ -name "*artifactory*" -o -name "*hashicorp.engineering*" \
  | xargs -r rm -f

echo "[bastion] Setting hosts entry: ${tfe_hosts_ip} ${tfe_fqdn}"
# Replace any existing entry so a changed IP is picked up on a re-run.
sed -i "/[[:space:]]${tfe_fqdn}\$/d" /etc/hosts
echo "${tfe_hosts_ip} ${tfe_fqdn}" >> /etc/hosts

echo "[bastion] Repairing any half-configured packages from an interrupted run."
dpkg --configure -a

echo "[bastion] Installing desktop and xrdp."
retry apt-get $APT_OPTS update -y
retry apt-get $APT_OPTS install -y xfce4 xfce4-terminal xrdp dbus-x11 curl ca-certificates

if dpkg -s google-chrome-stable > /dev/null 2>&1; then
  echo "[bastion] Google Chrome is already installed. Skipping."
else
  echo "[bastion] Installing Google Chrome."
  rm -f /tmp/chrome.deb
  retry curl -fsSL --retry 3 -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  retry apt-get $APT_OPTS install -y /tmp/chrome.deb
  rm -f /tmp/chrome.deb
fi

echo "[bastion] Configuring xrdp session for ${admin_username}."
echo "xfce4-session" > "/home/${admin_username}/.xsession"
chown "${admin_username}:$(id -gn "${admin_username}")" "/home/${admin_username}/.xsession"
adduser xrdp ssl-cert || true

systemctl enable xrdp
systemctl restart xrdp

echo "[bastion] Setup complete."

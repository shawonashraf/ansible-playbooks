#!/usr/bin/env bash
# Prepares the VM so the playbooks can run against it: python3 for the
# Ansible connection, curl for the shell tasks, and TARGET_USER with
# passwordless sudo so the become plays run without -K.
set -euo pipefail

if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y python3 curl ca-certificates
else
  # The Fedora box is the Cloud edition, not Workstation. Add what a stock
  # Workstation install already has and the playbooks assume: python3-libdnf5
  # for Ansible's dnf module, flatpak for playbook-flatpaks, and the
  # third-party repo definitions (disabled, as on Workstation) that hold
  # google-chrome for playbook-browsers.
  dnf install -y python3 python3-libdnf5 curl ca-certificates \
    flatpak fedora-workstation-repositories
fi

user="${TARGET_USER:-vagrant}"
if ! id "$user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$user"
fi
cat >"/etc/sudoers.d/$user" <<EOF
$user ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 "/etc/sudoers.d/$user"

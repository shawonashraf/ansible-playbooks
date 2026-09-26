#!/usr/bin/env bash
# Prepares the VM so the playbooks can run against it: python3 for the
# Ansible connection, curl for the shell tasks, and TARGET_USER with
# passwordless sudo so the become plays run without -K.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 curl ca-certificates

user="${TARGET_USER:-vagrant}"
if ! id "$user" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$user"
fi
cat >"/etc/sudoers.d/$user" <<EOF
$user ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 "/etc/sudoers.d/$user"

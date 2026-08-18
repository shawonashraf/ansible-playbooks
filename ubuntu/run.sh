#!/usr/bin/env bash
# Run the full Ubuntu post-install setup against this machine.
set -euo pipefail

cd "$(dirname "$0")"

VENV_BIN="../.venv/bin"

# Prefer the Ansible pinned by this repository over whatever is on PATH.
if [[ -x "$VENV_BIN/ansible-playbook" ]]; then
  ANSIBLE_PLAYBOOK="$VENV_BIN/ansible-playbook"
elif command -v ansible-playbook >/dev/null 2>&1; then
  ANSIBLE_PLAYBOOK="$(command -v ansible-playbook)"
else
  echo "ansible-playbook not found. Run 'uv sync' in the repository root." >&2
  exit 1
fi

# -K prompts for the sudo password. Secrets come from group_vars/all/vault.yml,
# which is optional: without it the run proceeds with empty secret values.
ARGS=(-K)

if [[ -f group_vars/all/vault.yml ]]; then
  if [[ -f .vault_pass ]]; then
    ARGS+=(--vault-password-file .vault_pass)
  else
    ARGS+=(--ask-vault-pass)
  fi
fi

exec "$ANSIBLE_PLAYBOOK" "${ARGS[@]}" "$@" playbook.yml

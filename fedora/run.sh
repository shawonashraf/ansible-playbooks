#!/usr/bin/env bash
# Run the full Fedora post-install setup against this machine.
set -euo pipefail

cd "$(dirname "$0")"

# Prompts for the sudo password. Secrets come from group_vars/all/vault.yml,
# which is optional: without it the run proceeds with empty secret values.
ARGS=(-K)

if [[ -f group_vars/all/vault.yml ]]; then
  if [[ -f .vault_pass ]]; then
    ARGS+=(--vault-password-file .vault_pass)
  else
    ARGS+=(--ask-vault-pass)
  fi
fi

exec ansible-playbook "${ARGS[@]}" "$@" playbook.yml

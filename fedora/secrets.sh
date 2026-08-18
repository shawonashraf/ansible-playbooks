#!/usr/bin/env bash
# Manage the encrypted secrets file at group_vars/all/vault.yml.
set -euo pipefail

cd "$(dirname "$0")"

VAULT="group_vars/all/vault.yml"
EXAMPLE="group_vars/all/vault.example.yml"
PASS_FILE=".vault_pass"

if [[ -f "$PASS_FILE" ]]; then
  VAULT_ARGS=(--vault-password-file "$PASS_FILE")
else
  VAULT_ARGS=(--ask-vault-pass)
fi

usage() {
  cat <<'USAGE'
Usage: ./secrets.sh <command>

  init    Create group_vars/all/vault.yml from the example template and encrypt it.
  edit    Open the encrypted vault in $EDITOR.
  view    Print the decrypted vault to stdout.
  rekey   Change the vault password.

The vault password is read from .vault_pass when that file exists (it is
gitignored); otherwise you are prompted for it.
USAGE
}

case "${1:-}" in
  init)
    if [[ -f "$VAULT" ]]; then
      echo "$VAULT already exists. Use './secrets.sh edit' to change it." >&2
      exit 1
    fi
    cp "$EXAMPLE" "$VAULT"
    ansible-vault encrypt "${VAULT_ARGS[@]}" "$VAULT"
    echo "Created and encrypted $VAULT. Edit it with './secrets.sh edit'."
    ;;
  edit|view|rekey)
    if [[ ! -f "$VAULT" ]]; then
      echo "$VAULT does not exist. Run './secrets.sh init' first." >&2
      exit 1
    fi
    ansible-vault "$1" "${VAULT_ARGS[@]}" "$VAULT"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac

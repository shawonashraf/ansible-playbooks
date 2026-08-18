#!/usr/bin/env bash
# Manage the encrypted secrets file at group_vars/all/vault.yml.
set -euo pipefail

cd "$(dirname "$0")"

VAULT="group_vars/all/vault.yml"
EXAMPLE="group_vars/all/vault.example.yml"
PASS_FILE=".vault_pass"
VENV_BIN="../.venv/bin"

# Prefer the Ansible pinned by this repository over whatever is on PATH.
if [[ -x "$VENV_BIN/ansible-vault" ]]; then
  ANSIBLE_VAULT="$VENV_BIN/ansible-vault"
elif command -v ansible-vault >/dev/null 2>&1; then
  ANSIBLE_VAULT="$(command -v ansible-vault)"
else
  echo "ansible-vault not found. Run 'uv sync' in the repository root." >&2
  exit 1
fi

if [[ -f "$PASS_FILE" ]]; then
  VAULT_ARGS=(--vault-password-file "$PASS_FILE")
else
  VAULT_ARGS=(--ask-vault-pass)
fi

usage() {
  cat <<'USAGE'
Usage: ./secrets.sh <command>

  init    Create group_vars/all/vault.yml from the example template, encrypted.
  edit    Open the encrypted vault in $EDITOR.
  view    Print the decrypted vault to stdout.
  rekey   Change the vault password.
  check   Verify vault.yml is encrypted. Use before committing.

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
    # Encrypt straight from the template to the destination. Writing plaintext
    # to vault.yml first would leave a decoy there if encryption then failed.
    "$ANSIBLE_VAULT" encrypt "${VAULT_ARGS[@]}" --output "$VAULT" "$EXAMPLE"
    echo "Created and encrypted $VAULT. Edit it with './secrets.sh edit'."
    ;;
  edit|view|rekey)
    if [[ ! -f "$VAULT" ]]; then
      echo "$VAULT does not exist. Run './secrets.sh init' first." >&2
      exit 1
    fi
    "$ANSIBLE_VAULT" "$1" "${VAULT_ARGS[@]}" "$VAULT"
    ;;
  check)
    if [[ ! -f "$VAULT" ]]; then
      echo "No $VAULT — nothing to check."
      exit 0
    fi
    if head -1 "$VAULT" | grep -q '^\$ANSIBLE_VAULT'; then
      echo "OK: $VAULT is encrypted."
    else
      echo "DANGER: $VAULT is NOT encrypted. Do not commit it." >&2
      exit 1
    fi
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

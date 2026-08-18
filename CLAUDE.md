# CLAUDE.md

Ansible playbooks that configure a freshly installed machine. `fedora/` is the
only live target; the repository is designed to be shareable, so nothing may be
hardcoded to a single user or machine.

## Environment

Ansible is pinned in this repository — do not rely on a global install.

```bash
uv sync                              # create/refresh .venv
.venv/bin/ansible-playbook --version
```

Use `uv add` / `uv remove` for dependency changes, never `pip`.

Note the repository depends on the full `ansible` distribution rather than
`ansible-core`: the flatpak playbook uses `community.general.flatpak` and
`flatpak_remote`, which `ansible-core` does not bundle.

## Layout

```
fedora/
  ansible.cfg              # inventory + output config
  inventory.ini            # localhost, local connection
  run.sh                   # entry point; handles -K and vault flags
  secrets.sh               # init/edit/view/rekey the encrypted vault
  playbook.yml             # import list, preflight first
  playbooks/               # one playbook per concern
  group_vars/all/
    config.yml             # committed plaintext config
    vault.yml              # committed ANSIBLE-VAULT ENCRYPTED (optional)
    vault.example.yml      # committed plaintext template
```

## Rules for changing playbooks

**Never hardcode a username or home directory.** Use `{{ target_user }}` and
`{{ target_user_home }}`. Both come from `group_vars/all/`; `target_user_home`
is a fact set by `playbook-preflight.yml`, so that playbook must stay first in
`playbook.yml`.

**Never declare `target_user` in a play-level `vars:` block.** Play vars beat
group_vars, so doing that silently reintroduces the hardcoding this layout
exists to remove.

**Never resolve the user from `ansible_user_id`.** Several plays run with
`become: true`, where facts are gathered as root and `ansible_user_id` returns
`root`. `config.yml` resolves the user on the controller via `SUDO_USER`/`USER`
instead.

**Reference secrets through their `config.yml` alias**, not the `vault_*` name:
use `{{ github_token }}`, not `{{ vault_github_token }}`. The aliases carry a
`| default('')` fallback that keeps runs working when `vault.yml` is absent.
Any task consuming a secret should skip or degrade when the value is empty
rather than fail.

**Never log a secret.** Set `no_log: true` on tasks that receive one.

## Secrets handling

`group_vars/all/vault.yml` is committed **encrypted**. Before committing any
change that touches it, confirm the first line is `$ANSIBLE_VAULT;1.1;AES256`.
Never commit `.vault_pass` (gitignored). Never write a real token into
`vault.example.yml` — that file is plaintext.

## Verifying changes

The playbooks target Fedora and cannot be fully run on macOS. What does work
anywhere:

```bash
cd fedora
../.venv/bin/ansible-playbook --syntax-check playbook.yml
```

To check that variables resolve, run a scratch playbook with `gather_facts:
false` from inside `fedora/` (so `group_vars/` is picked up) that debugs the
values, and test it both with and without a `vault.yml` present. Delete the
scratch file afterwards.

`playbook-preflight.yml` itself needs Linux — it uses `getent`.

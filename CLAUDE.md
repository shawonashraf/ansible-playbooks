# CLAUDE.md

Ansible playbooks that configure a freshly installed machine. `fedora/` is the
only live target; the repository is designed to be shareable, so nothing may be
hardcoded to a single user or machine.

## Environment

Ansible is pinned in this repository — do not rely on a global install.

```bash
uv sync   # create/refresh .venv
```

`fedora/run.sh` and `fedora/secrets.sh` resolve Ansible from `../.venv/bin`
first and fall back to `PATH`, so they work without activating anything. Keep
that resolution in place when editing either script.

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

`group_vars/all/vault.yml` is committed **encrypted**. Run `./secrets.sh check`
before committing any change that touches it; it exits non-zero on a plaintext
file. `.githooks/pre-commit` enforces the same rule, but only in clones that ran
`./fedora/secrets.sh install-hooks` — do not rely on it being active. Never commit `.vault_pass` (gitignored). Never write a real token into
`vault.example.yml` — that file is plaintext.

Never write plaintext to `vault.yml` as an intermediate step, even if you
encrypt it immediately after. A failure in between leaves a plaintext file at
the exact path the README tells the user to commit. `secrets.sh init` encrypts
from the template straight to the destination with `--output` for this reason.

## playbook-shell

Restores zsh from the repository named by `configs_repo`. Three things about it
are easy to break:

`setup.sh` in the configs repo is a **one-time bootstrap**, gated on
`~/.oh-my-zsh` being absent. It always overwrites `~/.zshrc` from its own copy,
so running it on every pass would fight Ansible's sanitised version and produce
a new `.backup-<timestamp>` file each run. Ansible owns `~/.zshrc` after the
first bootstrap.

**Never pass `--chsh` to `setup.sh`.** It shells out to `chsh`, which prompts for
a password under PAM and hangs an unattended run. The login shell is set with the
`user` module under `become: true`.

The profile is sanitised with a `(?m)` multiline `regex_replace`, not by
splitting on newlines. A `'\n'` written inside a YAML folded scalar (`>-`) does
not reach Jinja as a newline, so `split('\n')` silently returns a single element
and every `^`-anchored filter then matches nothing.

## Claude Code sync (in playbook-agents)

Install `claude-code-sync` with `uv tool install`, **never `uvx`**. Its
session-end hook stores the absolute path of whichever `claude-sync` ran the
install; an ephemeral uvx environment lives in the uv cache, so `uv cache clean`
would silently break the hook.

`claude-sync` shells out to plain `git clone` and `git push` with no credential
handling of its own, which is why the playbook writes `~/.git-credentials` at
mode 0600 and sets `credential.helper store` rather than embedding the token in
a remote URL. The backup repo is pushed to, so a URL-embedded token could not be
stripped afterwards the way playbook-shell strips its own.

`restore` is gated on the clone directory being absent. It overwrites `~/.claude`
from the backup, so running it every pass would discard local changes. Note that
`creates:` makes a task report empty stdout rather than marking it `skipped`, so
guard follow-up tasks on the output being non-empty, not on `is not skipped`.

Never run `claude-sync restore` while testing on a development machine: it shells
out to `claude plugin install` against the real `~/.claude`, regardless of
`CLAUDE_SYNC_HOME`.

## Commit signing (in playbook-devtools)

Generated keys use `ssh-keygen -N ''`. A passphrase would make every commit
prompt, because git's `ssh-keygen -Y sign` runs with no agent here.

The vault holds only the private key; the `.pub` is derived with
`ssh-keygen -y` and gated on `creates:`. Do not add a separate vault entry for
the public half — it would be one more thing to keep in step.

`commit.gpgsign=true` is global, so any breakage in the key makes *every* commit
fail, not just signed ones. Keep the key tasks ordered before the git_config
tasks.

Registering a signing key on GitHub needs the `admin:ssh_signing_key` scope,
which is distinct from `admin:public_key` and is not granted by a default
`gh auth login`. The play prints instructions rather than attempting it.

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

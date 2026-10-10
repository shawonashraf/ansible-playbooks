# CLAUDE.md

Ansible playbooks that configure a freshly installed machine. `ubuntu/` and
`fedora/` are parallel trees with the same layout, scripts and `group_vars`
contract; `ubuntu/` (targeting 26.04) is the one actively developed and the one
the Vagrant VM mirrors, `fedora/` is kept in step where a change is not
distro-specific. The repository is designed to be shareable, so nothing may be
hardcoded to a single user or machine.

## Environment

Ansible and ansible-lint are pinned in this repository — do not rely on a
global install.

```bash
uv sync   # create/refresh .venv
```

`run.sh`, `secrets.sh` and `vagrant/debug.sh` resolve Ansible from
`../.venv/bin` first and fall back to `PATH`, so they work without activating
anything. Keep that resolution in place when editing any of them.

Use `uv add` / `uv remove` for dependency changes, never `pip`.

Note the repository depends on the full `ansible` distribution rather than
`ansible-core`: the flatpak playbook uses `community.general.flatpak` and
`flatpak_remote`, which `ansible-core` does not bundle.

## Layout

```
ubuntu/                    # same layout under fedora/
  ansible.cfg              # inventory + output config; ubuntu adds become_plugins
  become_plugins/sudo.py   # ubuntu only, see sudo-rs below
  inventory.ini            # localhost, local connection
  hosts.ini                # gitignored; optional remote target for run.sh -i
  run.sh                   # entry point; handles -K and vault flags
  secrets.sh               # init/edit/view/rekey the encrypted vault
  playbook.yml             # import list, preflight first
  playbooks/               # one playbook per concern
  group_vars/all/
    config.yml             # committed plaintext config
    vault.yml              # committed ANSIBLE-VAULT ENCRYPTED (optional)
    vault.example.yml      # committed plaintext template
vagrant/
  Vagrantfile              # disposable Ubuntu VM (libvirt or virtualbox)
  bootstrap.sh             # python3 + TARGET_USER with passwordless sudo
  debug.sh                 # runs ubuntu/ playbooks against the VM
.githooks/pre-commit       # rejects plaintext vault*.yml; opt-in per clone
```

The playbook sets differ: ubuntu has `playbook-messaging` and
`playbook-zotero`, fedora has `playbook-creative`, `playbook-openbangla` and
`playbook-tailscale`. A fix to a shared playbook usually belongs in both trees;
check the other one before calling it done.

Ordering constraints in `ubuntu/playbook.yml` beyond preflight and github:
`playbook-zotero` must come after `playbook-utils` (its setup script needs
wget), `playbook-flatpaks` is commented out because flatpaks installed via
Ansible do not get desktop icons, and `playbook-gaming` is off by default.

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

**`configs_repo.profile` is deliberately `fedora` in `ubuntu/config.yml`.** The
configs repository has no `zshrc-ubuntu`, and the value only selects that file;
nothing OS-specific runs from it. Do not "fix" it to `ubuntu`.

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
handling of its own. With the default ssh URL that is the ssh key from
playbook-github. For a private https URL the playbook writes
`~/.git-credentials` at mode 0600 and sets `credential.helper store` rather
than embedding the token in a remote URL: the backup repo is pushed to, so a
URL-embedded token could not be stripped afterwards the way playbook-shell
strips its own.

`restore` is gated on the clone directory being absent. It overwrites `~/.claude`
from the backup, so running it every pass would discard local changes. Note that
`creates:` makes a task report empty stdout rather than marking it `skipped`, so
guard follow-up tasks on the output being non-empty, not on `is not skipped`.

Never run `claude-sync restore` while testing on a development machine: it shells
out to `claude plugin install` against the real `~/.claude`, regardless of
`CLAUDE_SYNC_HOME`.

## GitHub ssh key (in playbook-github)

Everything that touches GitHub uses one ssh key at `ssh_key_path`; there is no
token in the default flow. `playbook-github.yml` creates the key (from
`vault_ssh_private_key`, or `ssh-keygen` when the vault has none), pins GitHub's
host key, tests `ssh -T git@github.com`, and sets three facts the later plays
read: `github_ssh_ok`, `configs_repo_ready` and `claude_sync_ready`. It must
stay second in `playbook.yml`, right after preflight: devtools reads the `.pub`
it writes, and `commit.gpgsign=true` is global, so a missing key would make
*every* commit fail.

Gate private-repository work on the `*_ready` facts, not on `github_ssh_ok`:
the ready facts already allow https URLs through, which authenticate with
`github_token` instead of the key. Use `| default(false) | bool` on them so a
run with playbook-github commented out skips rather than errors.

A freshly generated key is unknown to GitHub, so the first run is expected to
skip the shell restore and the Claude Code sync and print the public key. That
is the designed flow, not a failure: register the key, rerun. Never turn the
skip into a `fail`.

Generated keys use `ssh-keygen -N ''`. A passphrase would make every commit
prompt, because git's `ssh-keygen -Y sign` runs with no agent here.

The vault holds only the private key; the `.pub` is derived with `ssh-keygen -y`
on every run so a key swapped in from the vault never leaves a stale `.pub`. Do
not add a separate vault entry for the public half.

Registering the key as a *signing* key on GitHub is separate from registering
it for access and needs the `admin:ssh_signing_key` scope via `gh`, which a
default `gh auth login` does not grant. The plays print instructions rather
than attempting it.

## sudo-rs (ubuntu only)

Ubuntu 25.10+ (so the 26.04 target) ships sudo-rs as `/usr/bin/sudo`. It
prints a custom `-p` prompt as `[sudo: <prompt>] Password:`, and Ansible's
builtin sudo plugin only matches
a line that starts with its prompt, so every `become: true` play fails with
"Timeout waiting for privilege escalation prompt". `ubuntu/become_plugins/sudo.py`
shadows the builtin through `become_plugins` in `ubuntu/ansible.cfg` and matches
the prompt anywhere in the line. Keep that setting; do not work around it with
`become_exe=/usr/bin/sudo.ws`, which only exists where classic sudo is also
installed.
The plugin copies the builtin's command builder rather than subclassing it:
because it shadows `ansible.plugins.become.sudo`, importing the builtin by that
name imports the plugin into itself. To check it is active, run an ad-hoc
`ansible -b -m ping -e ansible_become_password=wrong`: "Incorrect sudo
password" means the prompt was seen, a timeout means it was not.

## Verifying changes

Never run the playbooks against the development machine to test them; a
broken task leaves it half-configured. Cheap checks that run anywhere:

```bash
cd ubuntu   # or fedora
../.venv/bin/ansible-playbook --syntax-check playbook.yml
../.venv/bin/ansible-lint playbooks/playbook-foo.yml
```

To check that variables resolve, run a scratch playbook with `gather_facts:
false` from inside `ubuntu/` (so `group_vars/` is picked up) that debugs the
values, and test it both with and without a `vault.yml` present. Delete the
scratch file afterwards.

The real test is the Vagrant VM, which is wired to `ubuntu/` only. See the
README for host setup (libvirt, vagrant-libvirt).

```bash
cd vagrant
vagrant up
./debug.sh playbooks/playbook-media.yml   # one playbook, path relative to ubuntu/
./debug.sh                                # full run, like ubuntu/run.sh
vagrant destroy && vagrant up             # fresh machine
```

`debug.sh` regenerates `vagrant/inventory.ini` and `.vagrant-ssh-config` from
`vagrant ssh-config` (both gitignored), runs from inside `ubuntu/` so
`ansible.cfg` and `group_vars/` apply, and passes `-e target_user=vagrant` and
`-e target_user_home=/home/vagrant`. Those overrides exist because
`config.yml` resolves `target_user` from the controller's environment (your
host account, absent in the VM) and `target_user_home` only exists when
preflight runs. The VM user has passwordless sudo, so no `-K`. Extra arguments
pass through to `ansible-playbook`, including `--ask-vault-pass`. When
`vagrant ssh-config` fails because the shell lacks the `libvirt` group,
`debug.sh` reuses the previous ssh config rather than aborting.

Do not let `claude-sync restore` run in a context that reaches the real
`~/.claude` (see the Claude Code sync section); inside the VM it is fine.

To exercise a play against another real machine over ssh, put it in `hosts.ini`
and pass `-i hosts.ini`. An ad-hoc `-i host,` inventory does not load
`group_vars/`, so `target_user` comes back undefined and preflight fails on its
first task.

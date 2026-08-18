# ansible-playbooks

Ansible playbooks for automating post-OS-installation setup. Currently covers Fedora.

## Setup

The repository pins its own Ansible version, so you do not need Ansible installed globally:

```bash
uv sync
```

Then run it:

```bash
cd fedora
./run.sh
```

`run.sh` and `secrets.sh` use the pinned Ansible from `.venv` automatically, so
there is no environment to activate. They fall back to whatever `ansible` is on
your `PATH` if the virtualenv is missing. `run.sh` prompts for your sudo
password, and for the vault password if you have set up secrets. Extra arguments
are passed through to `ansible-playbook`:

```bash
./run.sh --syntax-check
```

## Configuration

Everything machine-specific lives in [`fedora/group_vars/all/`](fedora/group_vars/all/):

| File | Committed | Contents |
|---|---|---|
| `config.yml` | plaintext | `target_user`, private repo list, non-secret settings |
| `vault.yml` | encrypted | API tokens and other secrets. Optional. |
| `vault.example.yml` | plaintext | Template listing the keys `vault.yml` may define |

### target_user

`target_user` is no longer hardcoded. It defaults to the account running the
playbook, so a fresh clone works with no edits:

```yaml
target_user: "{{ lookup('env', 'SUDO_USER') | default(lookup('env', 'USER'), true) }}"
```

Replace that expression with a literal username in `config.yml` to configure a
different account. The home directory is looked up from the account itself, so
non-standard home paths work.

`playbook-preflight.yml` runs first and stops the run with a clear message if
`target_user` is unset, resolves to `root`, or names an account that does not
exist on the machine.

### Secrets

Secrets are stored in an [ansible-vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
encrypted `vault.yml`, which **is** committed. That way your tokens travel with
the repository and restore onto a new machine, while staying unreadable to
anyone without the vault password.

```bash
cd fedora
./secrets.sh init    # create vault.yml from the template and encrypt it
./secrets.sh edit    # open it in $EDITOR
./secrets.sh view    # print it decrypted
./secrets.sh rekey   # change the vault password
./secrets.sh check   # verify vault.yml is encrypted, before committing
```

To avoid retyping the password, write it to `fedora/.vault_pass` — that file is
gitignored, and `run.sh` and `secrets.sh` both pick it up automatically.

`vault.yml` is optional. Without it every secret resolves to an empty string and
the run proceeds normally, so anyone can clone this repository and use it
without your credentials.

> [!IMPORTANT]
> If you fork this repository you cannot decrypt the committed `vault.yml`.
> Delete it and run `./secrets.sh init` to create your own.

> [!WARNING]
> Only ever commit `vault.yml` in encrypted form. Run `./secrets.sh check`
> before committing; it exits non-zero if the file is plaintext.

There is a pre-commit hook that enforces this. Git hooks are not themselves
committed, so each clone has to opt in once:

```bash
cd fedora
./secrets.sh install-hooks
```

That points `core.hooksPath` at the committed [`.githooks/`](.githooks/)
directory. The hook rejects a commit that stages any `vault*.yml` which is not
`$ANSIBLE_VAULT` encrypted, and refuses `.vault_pass` outright. It reads the
*staged* content, not the working tree, so decrypting a vault locally is fine —
only committing it is blocked. `vault.example.yml` is exempt, being a plaintext
template by design.

### Git identity

`playbook-devtools.yml` sets the global git identity from the vault:

```yaml
vault_git_user_name: "Your Name"
vault_git_user_email: "you@example.com"
```

These are vaulted because an email address is personal data that should not sit
in a repository meant to be shared. Either value left empty leaves the
corresponding git setting alone, so a run without a vault will not wipe an
identity you already have.

Several things downstream depend on this: `claude-sync` commits your backups,
and shell-sync commits your profile. Both fall back to a placeholder identity
when git has none configured.

### Commit signing

`playbook-devtools.yml` configures git to sign every commit and tag with an ssh
key, matching `gpg.format=ssh`:

```
gpg.format                 ssh
user.signingkey            ~/.ssh/id_ed25519.pub
commit.gpgsign             true
tag.gpgsign                true
gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
```

The key comes from `vault_ssh_signing_key` when you provide one, so the same
signing identity carries across machines and one registered key verifies them
all. Only the private half is stored; the public key is derived from it. Leave
it empty and a passphrase-less ed25519 key is generated on the machine instead.
The key is written at mode `0600` into a `0700` `~/.ssh`.

A passphrase-less key is deliberate. Signing here runs outside any ssh-agent,
so a passphrase would make every commit prompt for it.

The play also writes `~/.ssh/allowed_signers` from your `git_user_email`, which
is what lets `git log --show-signature` verify your own commits instead of
reporting them as signed by an unknown key.

> [!IMPORTANT]
> Signing locally is not the same as GitHub showing commits as **Verified**.
> The public key must also be registered as a *signing* key, which is a
> different thing from an authentication key. The play prints the command:
>
> ```bash
> gh ssh-key add ~/.ssh/id_ed25519.pub --type signing --title fedora
> ```
>
> That needs the `admin:ssh_signing_key` scope, which `gh auth login` does not
> grant by default.

Set `git_signing.enabled: false` to leave git's signing settings alone.

### Private repositories

List repositories to restore onto a new machine in `config.yml`:

```yaml
private_repos:
  - name: dotfiles
    url: https://github.com/youruser/dotfiles.git
    dest: "{{ target_user_home }}/.dotfiles"
    version: main
    private: true   # clone using github_token
```

## Claude Code settings sync

`playbook-agents.yml` installs Claude Code, then restores its configuration
with [claude-code-sync](https://github.com/shawonashraf/claude-code-sync):
skills, hooks, agents, keybindings, the global `CLAUDE.md`, a redacted
`settings.json` and the plugin manifest. History, sessions and projects are
never included.

```yaml
claude_sync:
  backup_repo: "https://github.com/youruser/claude-code-backup.git"
  dest: "{{ target_user_home }}/Tools/claude-code-backup"
  install_hook: true
```

Set `backup_repo: ""` to skip. The restore runs once, gated on the clone not
existing, because it overwrites `~/.claude` from the backup and re-running it
would discard local changes made since. With `install_hook`, a `SessionEnd`
hook is added so every Claude Code session backs itself up on exit.

The tool is installed with `uv tool install`, not `uvx`. The hook records the
absolute path of the `claude-sync` that installed it, and an ephemeral `uvx`
environment lives in the uv cache, so `uv cache clean` would leave the hook
pointing at a binary that no longer exists.

After a restore, check the play output: it lists plugins that failed to
reinstall and any environment variables that were redacted out of
`settings.json` and need re-supplying by hand.

## Shell configuration

`playbook-shell.yml` restores zsh from a separate configs repository. It runs
last, because it installs `~/.zshrc` wholesale and would otherwise be overwritten
by the PATH blocks the devtools and agents playbooks add.

Point it at your own repository in `config.yml`:

```yaml
configs_repo:
  url: "https://github.com/youruser/configs.git"
  version: main
  dest: "{{ target_user_home }}/Projects/configs"
  profile: fedora     # selects shell/zshrc-fedora
```

Set `url: ""` to skip the playbook entirely. A private repository is cloned
using `github_token` from the vault; the token is stripped from the checkout's
remote URL afterwards so it is not left readable in `.git/config`.

> [!NOTE]
> The Claude Code sync above authenticates differently, through git's
> credential store, because it also has to *push*. Both read the same
> `github_token`.

The repository is expected to provide a `setup.sh` and `shell/zshrc-<profile>`.
`setup.sh` is run once, when `~/.oh-my-zsh` is missing, to install oh-my-zsh,
its plugins and the theme. Ansible manages `~/.zshrc` on every run after that,
so repeated runs stay idempotent. The login shell is switched to zsh with
Ansible's `user` module rather than `chsh`, which prompts for a password under
PAM and would hang an unattended run.

### Keeping credentials out of the profile

Shell profiles often export API tokens directly. Anything named in
`shell_secrets` is written to `~/.secrets.env` (mode `0600`) from the vault, and
the matching `export NAME=` lines are stripped from the installed `~/.zshrc`,
which sources that file at the top:

```yaml
shell_secrets:
  WANDB_API_KEY: "{{ wandb_api_key }}"
  HF_TOKEN: "{{ huggingface_token }}"
  PYPI_TOKEN: "{{ pypi_token }}"
```

Add entries as needed; the key is the variable name the shell sees. A secret
with no value in the vault is skipped rather than exported empty.

> [!NOTE]
> This strips the tokens from the copy in `$HOME`, not from your configs
> repository. Removing them at the source is a separate job.

## Selecting playbooks

Comment out any import you do not want in [`fedora/playbook.yml`](fedora/playbook.yml).
Leave `playbook-preflight.yml` first: the other playbooks depend on the variables
it resolves.

## Layout

```
pyproject.toml / uv.lock   pinned Ansible
CLAUDE.md                  conventions for AI agents working in this repo
fedora/
  ansible.cfg              inventory and output settings
  inventory.ini            localhost, local connection
  run.sh                   entry point
  secrets.sh               manage the encrypted vault
  playbook.yml             import list, preflight first
  playbooks/               one playbook per concern
  group_vars/all/          configuration and secrets
```

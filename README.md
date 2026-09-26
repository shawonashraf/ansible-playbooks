# ansible-playbooks

Ansible playbooks for automating post-OS-installation setup. Covers Fedora and
Ubuntu — `fedora/` and `ubuntu/` are parallel setups with the same layout and
configuration; the examples below use `fedora`, substitute `ubuntu` as needed.

## Setup

The repository pins its own Ansible version, so you do not need Ansible installed globally:

```bash
uv sync
```

### 1. Register an ssh key with GitHub

Do this first. The playbooks reach GitHub over ssh only: the key signs your
commits and clones your private configs and Claude Code backup repositories.
No token is needed, and no vault. Create the key on the machine being set up
and add it at <https://github.com/settings/ssh/new>, twice: once as an
**authentication** key, once as a **signing** key.

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

The key must be passphrase-less: signing runs outside any ssh-agent, so a
passphrase would make every commit prompt for it. If you skip this step the
first run generates the key, prints it, and leaves the shell restore and the
Claude Code sync for a second run once the key is registered.

### 2. Run it

```bash
cd fedora
./run.sh
```

`run.sh` and `secrets.sh` use the pinned Ansible from `.venv` automatically, so
there is no environment to activate. They fall back to whatever `ansible` is on
your `PATH` if the virtualenv is missing. `run.sh` prompts for your sudo
password, and for the vault password only if you have opted into the optional
vault (see [Secrets](#secrets)). Extra arguments are passed through to
`ansible-playbook`:

```bash
./run.sh --syntax-check
```

The playbooks configure the machine they run on by default. To configure
another machine over ssh instead, list it in a `hosts.ini` next to
`inventory.ini` (the file is gitignored) and pass it through:

```ini
workstation ansible_user=you
```

```bash
./run.sh -i hosts.ini
```

The sudo password prompt then applies to the remote account. `target_user`
resolves on the machine running Ansible, so set it explicitly in `config.yml`
when the remote account has a different name. Use a file rather than an
ad-hoc `-i host,` list: the latter does not pick up `group_vars/`.

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

The vault is optional and most setups do not need it. GitHub access goes
through the ssh key from step 1, so the vault only matters if you want API
keys written into `~/.secrets.env`, a git identity set for you, or one ssh key
shared across machines.

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

### GitHub access

`playbook-github.yml` runs right after preflight and owns the one ssh key the
rest of the run relies on: `playbook-devtools.yml` signs commits with it, and
`playbook-agents.yml` and `playbook-shell.yml` clone private repositories with
it. No GitHub token is involved.

The key comes from `vault_ssh_private_key` when you provide one, so the same
identity carries across machines and one registered key serves them all. Only
the private half is stored; the public key is derived from it. Leave it empty
and a passphrase-less ed25519 key is generated on the machine instead. The key
is written at mode `0600` into a `0700` `~/.ssh`, and GitHub's published host
key is pinned in `known_hosts` so the first clone neither prompts nor trusts
whatever answers.

A passphrase-less key is deliberate. Signing here runs outside any ssh-agent,
so a passphrase would make every commit prompt for it.

A freshly generated key is unknown to GitHub, so the play checks whether
`git@github.com` accepts it. When it does not, the play prints the public key
and the steps that clone private repositories over ssh are skipped for that
run. Add the key at <https://github.com/settings/ssh/new>, twice: once as an
authentication key, once as a signing key, then rerun. Everything else installs
on the first pass regardless.

### Commit signing

`playbook-devtools.yml` configures git to sign every commit and tag with that
key, matching `gpg.format=ssh`:

```
gpg.format                 ssh
user.signingkey            ~/.ssh/id_ed25519.pub
commit.gpgsign             true
tag.gpgsign                true
gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
```

The play also writes `~/.ssh/allowed_signers` from your `git_user_email`, which
is what lets `git log --show-signature` verify your own commits instead of
reporting them as signed by an unknown key.

> [!IMPORTANT]
> Signing locally is not the same as GitHub showing commits as **Verified**.
> The public key must also be registered as a *signing* key, which is a
> different thing from an authentication key. Both are added on the same
> settings page; pick the key type when adding it.

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
  backup_repo: "git@github.com:youruser/claude-code-backup.git"
  dest: "{{ target_user_home }}/Tools/claude-code-backup"
  install_hook: true
```

Set `backup_repo: ""` to skip. An ssh URL is cloned with the key from
`playbook-github.yml` and the whole sync is skipped until GitHub accepts that
key. A private https URL is authenticated with `github_token` through git's
credential store instead, because the backup is also pushed to and a token
embedded in the remote URL could not be stripped afterwards.

The restore runs once, gated on the clone not
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
  url: "git@github.com:youruser/configs.git"
  version: main
  dest: "{{ target_user_home }}/Projects/configs"
  profile: fedora     # selects shell/zshrc-fedora
```

Set `url: ""` to skip the playbook entirely. An ssh URL is cloned with the
key from `playbook-github.yml`; until GitHub accepts that key the restore and
the switch of the login shell are skipped, so you are never left with zsh as
the login shell and no profile. A private https URL is cloned using
`github_token` from the vault instead; the token is stripped from the
checkout's remote URL afterwards so it is not left readable in `.git/config`.

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
Leave `playbook-preflight.yml` first and `playbook-github.yml` second: the other
playbooks depend on the variables and the ssh key they set up.

## Debugging in a Vagrant VM

The playbooks normally configure the machine they run on, which makes them
awkward to iterate on: a broken task can leave your workstation half-configured.
[`vagrant/`](vagrant/) builds a disposable Ubuntu VM to run them against
instead — currently wired to the `ubuntu/` playbooks, since that is the
environment it mirrors.

One-time host setup, for the libvirt provider:

```bash
sudo apt install -y libvirt-daemon-system qemu-system-x86 libvirt-dev
sudo usermod -aG libvirt,kvm "$USER"        # takes effect at the next login
curl -LO https://releases.hashicorp.com/vagrant/2.4.9/vagrant_2.4.9-1_amd64.deb
sudo apt install ./vagrant_2.4.9-1_amd64.deb
vagrant plugin install vagrant-libvirt
```

Then the debug loop:

```bash
cd vagrant
vagrant up                                 # boot the VM and bootstrap it
./debug.sh playbooks/playbook-media.yml     # one playbook, path relative to ubuntu/
./debug.sh                                  # the full run, like ubuntu/run.sh
vagrant destroy && vagrant up               # throw the machine away and start over
```

`debug.sh` builds a throwaway inventory from `vagrant ssh-config`, so the
VM's address and key always match the running machine, and runs the Ansible
pinned by this repository from `ubuntu/`, so `ansible.cfg` and `group_vars`
apply as in a normal run. Extra arguments pass through to `ansible-playbook`,
including vault flags when `vault.yml` exists:

```bash
./debug.sh playbooks/playbook-media.yml --syntax-check
./debug.sh --ask-vault-pass
```

Two variables a normal run resolves that a standalone playbook cannot:

- `target_user` defaults to the account running Ansible, which in the VM
  would resolve to your host account — an account that does not exist there.
  `debug.sh` passes `-e target_user=vagrant`; set `TARGET_USER` to debug a
  different account (created by the bootstrap with passwordless sudo, so no
  `-K` is needed).
- `target_user_home` is set by `playbook-preflight.yml`, which never runs
  when you target a single playbook. `debug.sh` provides it as
  `/home/$TARGET_USER`; point `TARGET_USER_HOME` at the real path for
  accounts with a non-standard home. In the full run the extra variable has
  the same precedence as preflight's, so set it there too.

The VM itself is configured through environment variables on `vagrant up`:

| Variable | Default | Controls |
|---|---|---|
| `BOX` | `bento/ubuntu-24.04` | The base box; override to test another release |
| `TARGET_USER` | `vagrant` | The account the playbooks configure |
| `VM_CPUS` | `4` | VM CPUs |
| `VM_MEMORY` | `8192` | VM memory in MB |

> [!NOTE]
> Until your next login, shells started from an existing desktop session do
> not carry the `libvirt` group. Until then, prefix Vagrant's daemon-touching
> commands (`up`, `halt`, `destroy`, `ssh`) with `sudo -u "$USER"` — sudo
> re-reads `/etc/group`, so the group is already visible to it. `debug.sh`
> itself keeps working in that state: when it cannot reach libvirt it reuses
> the ssh config from the last successful run, since the VM's address does
> not change while it runs.

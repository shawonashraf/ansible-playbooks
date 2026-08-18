# ansible-playbooks

Ansible playbooks for automating post-OS-installation setup. Currently covers Fedora.

## Setup

The repository pins its own Ansible version, so you do not need Ansible installed globally:

```bash
uv sync
```

Then configure and run:

```bash
cd fedora
../.venv/bin/ansible-playbook --version   # or: source ../.venv/bin/activate
./run.sh
```

`run.sh` prompts for your sudo password, and for the vault password if you have
set up secrets.

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
> Only ever commit `vault.yml` in encrypted form. Verify with
> `head -1 fedora/group_vars/all/vault.yml` — it must read `$ANSIBLE_VAULT;1.1;AES256`.

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

## Selecting playbooks

Comment out any import you do not want in [`fedora/playbook.yml`](fedora/playbook.yml).
Leave `playbook-preflight.yml` first: the other playbooks depend on the variables
it resolves.

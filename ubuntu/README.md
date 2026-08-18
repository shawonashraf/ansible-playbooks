# ubuntu

Ubuntu (26.04) post installation steps automated with ansible. A port of the
[fedora setup](../fedora/) — same layout, same configuration, apt instead of
dnf.

## playbooks

> [!NOTE]
> If you don't need specific playbooks you can comment them out in the `playbook.yml` file.
> Keep `playbook-preflight.yml` first: it resolves `target_user` and
> `target_user_home`, which the devtools, agents and flatpaks playbooks use.

## configuration

Machine-specific settings live in `group_vars/all/`. See the
[repository README](../README.md#configuration) for how `target_user`,
secrets and private repositories are configured.

```bash
./secrets.sh init   # set up encrypted secrets
./run.sh            # run everything
```

## differences from the fedora setup

| Topic | Difference |
|---|---|
| Codecs | `ubuntu-restricted-extras` + `libavcodec-extra` instead of RPM Fusion. The mscorefonts EULA is pre-accepted via debconf so the run stays unattended. |
| Flatpak | Not preinstalled on Ubuntu; `playbook-flatpaks.yml` installs it first. |
| Bottles | No deb package; installed as a flatpak instead. |
| onefetch | No archive package (Fedora uses a copr); installed from the project's release .deb. |
| Steam | Package is named `steam-installer` (multiverse). |
| Shell profile | Reuses `shell/zshrc-fedora` from the configs repository — `configs_repo.profile` stays `fedora` on purpose, so other projects need no renaming. |

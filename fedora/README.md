# fedora

Fedora post installation steps automated with ansible.

## playbooks

> [!NOTE]
> If you don't need specific playbooks you can comment them out in the `playbook.yml` file.
> Keep `playbook-preflight.yml` first: it resolves `target_user` and
> `target_user_home`, which the devtools, agents and flatpaks playbooks use.
> Keep `playbook-github.yml` second: it creates the ssh key devtools signs with
> and decides whether the agents and shell playbooks can clone over ssh.

This directory contains a set of ansible playbooks for setting up some preferred
applications after setup.

## configuration

Machine-specific settings live in `group_vars/all/`. See the
[repository README](../README.md#configuration) for how `target_user`,
secrets and private repositories are configured.

Register an ssh key with GitHub first, then run everything. The key is what
clones your private repositories and signs your commits; no token or vault
is required.

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub   # add at https://github.com/settings/ssh/new, as authentication AND signing key
./run.sh                    # run everything
```

`./secrets.sh init` sets up the optional encrypted vault for API keys and a
git identity; it is not needed for the run to complete.


## what's not covered

| Topic | Reason |
|---|---|
| CUDA Toolkit installation | Check [RPMFusion/Howto/CUDA](https://rpmfusion.org/Howto/CUDA) and [Nvidia CUDA Toolkit Downloads](https://developer.nvidia.com/cuda-downloads). Also ensure that you install a compatible gcc compiler since the system version is always ahead by a version or two. |
| Secure Boot Setup | Check [RPMFusion/Howto/Secureboot](https://rpmfusion.org/Howto/Secure%20Boot). |
| Gnome shell extensions | Install based on your preferences. |
| VPNs and other email clients | Same as above. |

> [!TIP]
> If you're using a new gen Thinkpad (e.g. P1 Gen 7 or newer), read the [OMGLinux guide](https://www.omglinux.com/boot-linux-modern-lenovo-thinkpads-bios-setting/) on how to enable secure boot for non-Microsoft operating systems in the bios.


> [!TIP]
> If you've a dual gpu laptop (iGPU+dGPU), use the following as the launcher command to run games on the dGPU: `%command% -graphicsadapter=0` if games run on iGPU by default.


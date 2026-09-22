# sudo become plugin that also understands sudo-rs.
#
# Ubuntu 25.10+ ships sudo-rs as /usr/bin/sudo. When asked for a custom prompt
# with -p it prints "[sudo: <prompt>] Password:" instead of the prompt verbatim.
# Ansible's builtin plugin only accepts a line that *starts* with its prompt,
# so it never sees the password request and every become play dies with
# "Timeout waiting for privilege escalation prompt". This subclass matches the
# prompt anywhere in the line and adds sudo-rs's error wording. It shadows the
# builtin "sudo" through become_plugins in ansible.cfg, so plays need no
# change, and it behaves identically against classic sudo.
from __future__ import annotations

DOCUMENTATION = """
    name: sudo
    short_description: Substitute User DO (classic sudo and sudo-rs)
    description:
        - >-
          The builtin sudo become plugin, extended to recognise the password
          prompt sudo-rs prints, which wraps the requested prompt in
          "[sudo ...] Password" rather than printing it verbatim.
    author: ansible (@core)
    version_added: "2.8"
    options:
        become_user:
            description: User you 'become' to execute the task
            default: root
            ini:
              - section: privilege_escalation
                key: become_user
              - section: sudo_become_plugin
                key: user
            vars:
              - name: ansible_become_user
              - name: ansible_sudo_user
            env:
              - name: ANSIBLE_BECOME_USER
              - name: ANSIBLE_SUDO_USER
            keyword:
              - name: become_user
        become_exe:
            description: Sudo executable
            default: sudo
            ini:
              - section: privilege_escalation
                key: become_exe
              - section: sudo_become_plugin
                key: executable
            vars:
              - name: ansible_become_exe
              - name: ansible_sudo_exe
            env:
              - name: ANSIBLE_BECOME_EXE
              - name: ANSIBLE_SUDO_EXE
            keyword:
              - name: become_exe
        become_flags:
            description: Options to pass to sudo
            default: -H -S -n
            ini:
              - section: privilege_escalation
                key: become_flags
              - section: sudo_become_plugin
                key: flags
            vars:
              - name: ansible_become_flags
              - name: ansible_sudo_flags
            env:
              - name: ANSIBLE_BECOME_FLAGS
              - name: ANSIBLE_SUDO_FLAGS
            keyword:
              - name: become_flags
        become_pass:
            description: Password to pass to sudo
            required: False
            vars:
              - name: ansible_become_password
              - name: ansible_become_pass
              - name: ansible_sudo_pass
            env:
              - name: ANSIBLE_BECOME_PASS
              - name: ANSIBLE_SUDO_PASS
            ini:
              - section: sudo_become_plugin
                key: password
        sudo_chdir:
            description: Directory to change to before invoking sudo; can avoid permission errors when dropping privileges.
            type: string
            required: False
            version_added: '2.19'
            vars:
              - name: ansible_sudo_chdir
            env:
              - name: ANSIBLE_SUDO_CHDIR
            ini:
              - section: sudo_become_plugin
                key: chdir
"""

import re
import shlex

from ansible.errors import AnsibleError
from ansible.module_utils.common.text.converters import to_bytes
from ansible.plugins.become import BecomeBase

# Not a subclass of the builtin: this file shadows ansible.plugins.become.sudo
# in the plugin loader, so importing the builtin by that name would import
# this file back into itself. build_become_command is the builtin's, verbatim.


class BecomeModule(BecomeBase):

    name = 'sudo'

    # Classic sudo wording first, sudo-rs wording second.
    fail = ('Sorry, try again.', 'Authentication failed, try again.')
    missing = (
        'Sorry, a password is required to run sudo',
        'sudo: a password is required',
        'Authentication required but not attempted',
    )

    def check_password_prompt(self, b_output: bytes) -> bool:
        """Accept the prompt anywhere in a line, not only at its start."""
        if self.prompt:
            b_prompt = to_bytes(self.prompt).strip()
            return any(b_prompt in line for line in b_output.splitlines())
        return False

    def build_become_command(self, cmd, shell):
        super().build_become_command(cmd, shell)

        if not cmd:
            return cmd

        becomecmd = self.get_option('become_exe') or self.name

        flags = self.get_option('become_flags') or ''
        prompt = ''
        if self.get_option('become_pass'):
            self.prompt = '[sudo via ansible, key=%s] password:' % self._id
            if flags:
                reflag = []
                for flag in shlex.split(flags):
                    if flag in ('-n', '--non-interactive'):
                        continue
                    elif not flag.startswith('--'):
                        # handle -XnxxX flags only
                        flag = re.sub(r'^(-\w*)n(\w*.*)', r'\1\2', flag)
                    reflag.append(flag)
                flags = shlex.join(reflag)

            prompt = '-p "%s"' % (self.prompt)

        user = self.get_option('become_user') or ''
        if user:
            user = '-u %s' % (user)

        if chdir := self.get_option('sudo_chdir'):
            try:
                becomecmd = f'{shell.CD} {shlex.quote(chdir)} {shell._SHELL_AND} {becomecmd}'
            except AttributeError as ex:
                raise AnsibleError(f'The {shell._load_name!r} shell plugin does not support sudo chdir. It is missing the {ex.name!r} attribute.')

        return ' '.join([becomecmd, flags, prompt, user, self._build_success_command(cmd, shell)])

# SSH Merge Hook

This directory declares the `ssh` merge-hook instance. Its declarative source
family is `config.d/`, which contains ordered SSH config fragments. Prefer
`*.ssh_config` fragments for editor highlighting; the hook still accepts
legacy `*.ssh-config` fragments.

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/ssh.sh`.

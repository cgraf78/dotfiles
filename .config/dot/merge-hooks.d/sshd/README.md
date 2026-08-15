# SSH server policy

`dot update` installs the fragments in `sshd_config.d` only when it is run as
root on a host with an OpenSSH server and `/etc/ssh/sshd_config.d` support.
Changes are validated before the active SSH service is reloaded.

# Home Network Hosts

## nas

- Purpose: NAS and SSH jump host for `taylor`, `metro`, and `bevo2`
- OS: Arch Linux
- Access: direct SSH as `nas`
- Cron: `cronie.service` with `CROND` journal entries
- Notes: home network entry point; commonly runs `dot update --cron` and
  `ht_list_package_updates`

## taylor

- Purpose: Debian host with `openclaw` workloads
- OS: Debian 13 (trixie)
- Access: SSH via `nas`
- Cron: `cron.service` with `CRON` journal entries
- Users: `chris`, `openclaw`
- Notes: `openclaw` healthcheck job is expected; unattended-upgrades is
  security-only with auto reboot at `04:20`

## metro

- Purpose: Ubuntu host
- OS: Ubuntu development branch
- Access: SSH via `nas`
- Cron: `cron.service` with `CRON` journal entries
- Users: `chris`
- Notes: unattended-upgrades is security-only with auto reboot at `04:20`

## bevo2

- Purpose: WSL2 host
- OS: Arch Linux on WSL2 with systemd enabled
- Access: SSH as `bevo2`; `nas` is also used as a jump host
- Cron: `cronie.service` with `CROND` journal entries
- Users: `chris`
- Notes: root and `chris` both run `dot update --cron`; earlier checks can
  look empty if only Debian-style `cron` service names are queried

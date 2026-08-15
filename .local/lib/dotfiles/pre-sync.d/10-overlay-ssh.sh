# shellcheck shell=bash
# Prepare client-owned SSH host aliases before dot may clone private overlays.
# The standalone engine owns only this generic pre-sync lifecycle; all SSH
# syntax, identity-file policy, and managed markers remain in dotfiles.

prepare() {
  local descriptor_dir destination file name origin body target_host proxy_cmd
  local block nullglob_was_set=0
  local -a blocks=()

  dot_xdg_path config dot/overlays.d || return
  descriptor_dir=$REPLY
  destination=$HOME/.ssh/config

  shopt -q nullglob && nullglob_was_set=1
  shopt -s nullglob
  for file in "$descriptor_dir"/*.ssh; do
    [[ -f $file && ! -L $file && -r $file ]] || return 1
    grep -qm1 '^Host ' "$file" || continue
    name=${file##*/}
    name=${name%.ssh}
    origin=$(realpath "$file") || return 1
    body=$(<"$file")
    body=${body%$'\n'}

    if [[ $body != *ProxyCommand* ]]; then
      target_host=$(printf '%s\n' "$body" |
        awk '/^[[:space:]]+HostName / { print $2; exit }')
      if [[ -n $target_host && -f $destination && ! -L $destination ]]; then
        proxy_cmd=$(awk -v host="$target_host" '
          /^Host / { active=($2 == host) }
          active && /^[[:space:]]+ProxyCommand / {
            sub(/^[[:space:]]+/, "  ")
            print
            exit
          }
        ' "$destination")
        [[ -z $proxy_cmd ]] || body=$body$'\n'$proxy_cmd
      fi
    fi

    block=$(dot_managed_block_build \
      "# dot-managed:overlay-ssh:$name" "$origin" "$body") || return
    blocks+=("$block")
  done
  [[ $nullglob_was_set -eq 1 ]] || shopt -u nullglob

  [[ ${#blocks[@]} -gt 0 || -f $destination ]] || return 0
  dot_managed_block_merge_family \
    "$destination" '# dot-managed:overlay-ssh:' "${blocks[@]}"
}

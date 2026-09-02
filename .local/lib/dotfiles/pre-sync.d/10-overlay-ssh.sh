# shellcheck shell=bash
# Prepare client-owned SSH host aliases before dot may clone private overlays.
# The standalone engine owns only this generic pre-sync lifecycle; all SSH
# syntax, identity-file policy, and managed markers remain in dotfiles.

prepare() {
  local stage=${DOT_PRE_SYNC_STAGE:-reconcile}
  local destination entry name path url descriptor optional sync extra
  local companion origin body target_host proxy_cmd block
  local -a blocks=()

  # A pre-profile Dot runtime supplies the same validated OVERLAYS records but
  # no stage. Treat only that absent value as its historical one-pass
  # reconciliation so the provider can update and re-exec the new runtime.
  case $stage in
    prepare | reconcile) ;;
    *)
      dot_hook_warn "invalid overlay SSH stage: $stage"
      return 1
      ;;
  esac

  destination=$HOME/.ssh/config

  # Standalone Dot passes only selected, descriptor-valid, host/platform-
  # eligible records through its one-use worker context. Derive companions
  # from those records instead of rediscovering every configured overlay.
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    # shellcheck disable=SC2034 # Decode and validate the complete context record.
    IFS='|' read -r name path url descriptor optional sync extra <<<"$entry"
    [[ -z $extra && -n $name && -n $descriptor && -n $sync ]] || return 1
    [[ $sync == git ]] || continue
    companion=${descriptor%.conf}.ssh
    [[ -e $companion || -L $companion ]] || continue
    [[ -f $companion && ! -L $companion && -r $companion ]] || return 1
    grep -qm1 '^Host ' "$companion" || continue
    origin=$(realpath "$companion") || return 1
    body=$(<"$companion")
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

  [[ ${#blocks[@]} -gt 0 || -f $destination ]] || return 0
  if [[ $stage == prepare ]]; then
    # Phase one does not yet know the final profile, so it may refresh only the
    # supplied blocks and must preserve other members of the managed family.
    dot_managed_block_merge "$destination" "${blocks[@]}"
  else
    dot_managed_block_merge_family \
      "$destination" '# dot-managed:overlay-ssh:' "${blocks[@]}"
  fi
}

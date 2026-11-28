# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# Choose how this account's Git reaches github.com: SSH (Git's default, no
# configuration) or HTTPS authenticated by the account's read-scoped token.
#
# Policy is data in the `github-transport/policy.d` family. Every record uses
# the profile-selector grammar and precedence (`version`, optional `user`,
# optional `host`, plus `transport`), so fleet policy reads the same way as
# profile policy: a user+host record beats a user-only or host-only record,
# which beats the default, and disagreeing records at the winning level are an
# error. The default is the one record without `user` or `host`; it must live
# in `default.replace/`, so an overlay replaces the base default instead of
# conflicting with it. Flipping the fleet default is therefore one overlay
# file, with per-account exceptions as ordinary records.
#
# HTTPS is applied as a managed block in ~/.gitconfig. Git reads ~/.gitconfig
# in addition to the XDG config, so the block works on accounts that have no
# global config at all (root and editor-profile accounts) without touching the
# development overlay's tracked ~/.config/git/config. The dev overlay's `git`
# hook writes ~/.gitconfig only when Git skips the XDG file, which no
# supported Git does while ~/.gitconfig exists, so the two hooks never write
# the same file in one update.

_GITHUB_TRANSPORT_FAMILY=github-transport/policy.d
_GITHUB_TRANSPORT_MARKER='# dot-managed:github-transport'

# Print `level<TAB>transport` for one record when it matches this account, or
# nothing when it does not. Returns 1 with a warning for an invalid record, so
# one bad file stops the hook before any configuration changes.
_github_transport_record() {
  local file=$1 is_default=$2 current_user=$3
  local line key value version='' user='' host='' transport='' seen=' ' level=0
  local has_user=false has_host=false

  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ $line != *=* ]]; then
      dot_hook_warn "    warning: $file: expected key=value, got: $line"
      return 1
    fi
    key=${line%%=*}
    value=${line#*=}
    if [[ $seen == *" $key "* ]]; then
      dot_hook_warn "    warning: $file: duplicate key: $key"
      return 1
    fi
    seen+="$key "
    case $key in
      version) version=$value ;;
      user)
        user=$value
        has_user=true
        ;;
      host)
        host=$value
        has_host=true
        ;;
      transport) transport=$value ;;
      *)
        dot_hook_warn "    warning: $file: unknown key: $key"
        return 1
        ;;
    esac
  done <"$file"

  if [[ $version != 1 ]]; then
    dot_hook_warn "    warning: $file: version must be 1"
    return 1
  fi
  case $transport in
    ssh | https) ;;
    *)
      dot_hook_warn "    warning: $file: transport must be ssh or https"
      return 1
      ;;
  esac
  # A present identity key must hold a valid value: Dot's selector rules for
  # user names and host names, so an empty `host=` or a lone `.` can never
  # silently widen a record to every account. Host values also feed Dot's
  # filter grammar, where `,` and `!` have meaning, which these classes
  # exclude.
  if [[ $has_user == true && ! $user =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
    dot_hook_warn "    warning: $file: invalid user value"
    return 1
  fi
  host=${host%.}
  if [[ $has_host == true && ! $host =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]]; then
    dot_hook_warn "    warning: $file: invalid host value"
    return 1
  fi
  if [[ $is_default == true && ($has_user == true || $has_host == true) ]]; then
    dot_hook_warn "    warning: $file: the default record must not set user or host"
    return 1
  fi
  if [[ $is_default == false && $has_user == false && $has_host == false ]]; then
    dot_hook_warn "    warning: $file: only default.replace/ may omit both user and host"
    return 1
  fi

  if [[ $has_user == true ]]; then
    [[ $user == "$current_user" ]] || return 0
    level=$((level + 1))
  fi
  if [[ $has_host == true ]]; then
    # Reuse Dot's host identity (short, lowercased kernel host name) so this
    # policy matches exactly the hosts profile selectors match.
    dot_hook_host_match "$host" || return 0
    level=$((level + 1))
  fi
  printf '%s\t%s\n' "$level" "$transport"
}

# Print the transport this account should use. Without any policy the result
# is ssh, which leaves Git untouched, so a host that cannot read an overlay
# keeps working as before.
_github_transport_resolve() {
  local current_user family file relative is_default match level transport
  # Transports seen at each specificity (0 default, 1 user or host, 2 both).
  # Every record is validated, but only the winning level is checked for
  # disagreement, matching profile selectors: a lower-level conflict is
  # irrelevant once a more specific record applies.
  local seen0='' seen1='' seen2='' winners

  current_user=$(id -un) || return 1
  family=$(dot_hook_family "$_GITHUB_TRANSPORT_FAMILY") || return 1
  while IFS= read -r file; do
    relative=${file#"$family"/}
    is_default=false
    case $relative in
      default.replace/*) is_default=true ;;
      */*)
        dot_hook_warn "    warning: $relative: records belong at the top level or in default.replace/"
        return 1
        ;;
    esac
    match=$(_github_transport_record "$file" "$is_default" "$current_user") || return 1
    [[ -n $match ]] || continue
    level=${match%%$'\t'*}
    transport=${match#*$'\t'}
    case $level in
      0) seen0+=" $transport" ;;
      1) seen1+=" $transport" ;;
      2) seen2+=" $transport" ;;
    esac
  done < <(dot_hook_family_files_matching "$_GITHUB_TRANSPORT_FAMILY" '*.conf' '*.replace/*.conf')

  winners=${seen2:-${seen1:-$seen0}}
  if [[ $winners == *ssh* && $winners == *https* ]]; then
    dot_hook_warn "    warning: GitHub transport records disagree at the same specificity; leaving Git unchanged"
    return 1
  fi
  case $winners in
    *https*) printf 'https\n' ;;
    *) printf 'ssh\n' ;;
  esac
}

# The HTTPS block. Every SSH spelling of github.com that Git accepts without an
# SSH host alias is rewritten, so existing remotes switch without editing any
# checkout. Aliases defined in ~/.ssh/config (such as `github-work:`) are
# deliberately left alone: they name a specific key, not this account's
# default. `helper =` first clears helpers inherited from broader config, so
# GitHub requests always use the policy's token file. Git runs `!` helpers
# through the shell, which expands $HOME for whichever account runs Git.
_github_transport_https_body() {
  cat <<'EOF'
[url "https://github.com/"]
	insteadOf = git@github.com:
	insteadOf = ssh://git@github.com/
	insteadOf = ssh://git@github.com:22/
	insteadOf = ssh://github.com/
[credential "https://github.com"]
	helper =
	helper = "!\"$HOME/.local/lib/dotfiles/git-credential-github-pat\""
EOF
}

# The managed-block helpers publish by atomic rename, which cannot update a
# symlink's target and would replace or delete the link itself. A symlinked
# ~/.gitconfig belongs to whatever manages its target, so report it instead.
_github_transport_refuse_symlink() {
  local dst=$1
  [[ -L $dst ]] || return 0
  dot_hook_warn "    warning: ~/.gitconfig is a symlink; set the GitHub transport in its target by hand"
  return 1
}

_github_transport_apply_https() {
  local dst=$1 family block

  _github_transport_refuse_symlink "$dst" || return 1
  family=$(dot_hook_family "$_GITHUB_TRANSPORT_FAMILY") || return 1
  block=$(dot_managed_block_build "$_GITHUB_TRANSPORT_MARKER" "$family" \
    "$(_github_transport_https_body)") || return 1
  dot_managed_block_merge_family "$dst" "$_GITHUB_TRANSPORT_MARKER" "$block"
}

# Remove only the managed block. The file is deleted only when nothing else
# remains, so an SSH account never gains a ~/.gitconfig and hand-written
# settings always survive.
_github_transport_apply_ssh() {
  local dst=$1 current rest

  [[ -f $dst ]] || return 0
  current=$(<"$dst")
  rest=$(dot_managed_block_strip_family "$_GITHUB_TRANSPORT_MARKER" "$current") || return 1
  [[ $rest != "$current" ]] || return 0
  _github_transport_refuse_symlink "$dst" || return 1
  rest=${rest#"${rest%%[![:space:]]*}"}
  rest=${rest%"${rest##*[![:space:]]}"}
  if [[ -n $rest ]]; then
    dot_write_text_if_changed "$dst" "$rest"$'\n'
  else
    rm -f "$dst"
  fi
}

# True when the token file the credential helper reads holds a first line.
# Only presence is checked: validity needs the network, and an expired token
# is a doctor-level problem rather than a reason to rewrite Git config.
_github_transport_has_token() {
  local token=''
  [[ -r $HOME/.config/gh/github-pat ]] || return 1
  IFS= read -r token <"$HOME/.config/gh/github-pat" || [[ -n $token ]] || return 1
  token=${token%$'\r'}
  [[ -n $token ]]
}

merge() {
  _dot_tool_present github-transport || return 0
  local transport dst=$HOME/.gitconfig

  transport=$(_github_transport_resolve) || return 1
  case $transport in
    https)
      if ! _github_transport_has_token; then
        # Installing the block without a token makes every private fetch
        # fail, and optional overlays fail silently, so the overlay carrying
        # the fix could never arrive. Keep SSH and fail the hook loudly.
        dot_hook_warn "    warning: policy selects GitHub HTTPS but ~/.config/gh/github-pat is missing or empty; keeping SSH"
        _github_transport_apply_ssh "$dst" || true
        return 1
      fi
      dot_hook_log "  GitHub transport: https"
      _github_transport_apply_https "$dst"
      ;;
    *) _github_transport_apply_ssh "$dst" ;;
  esac
}

# Zsh parses the large Git completion definition on its first use. Keep a
# validated compiled copy so the first Git completion stays interactive-fast.
_cache_zsh_git_completion() {
  emulate -L zsh

  ((${+functions[_tool_cache_dir]})) || return 0
  _tool_cache_dir || return 0
  local cache_root="$REPLY/zsh-completions"
  local cache_base="$cache_root/$ZSH_VERSION"
  local dir source=""
  local -a source_fpath

  # Re-sourcing must rediscover the original definition, not our cache.
  for dir in "$fpath[@]"; do
    [[ "$dir" == "$cache_base/"* ]] || source_fpath+=("$dir")
  done
  fpath=("$source_fpath[@]")

  for dir in "$source_fpath[@]"; do
    if [[ -f "$dir/_git" && -r "$dir/_git" ]]; then
      source="$dir/_git"
      break
    fi
  done
  [[ -n "$source" ]] || return 0

  # Import only zstat so the module does not add a global `stat` builtin.
  zmodload -F zsh/stat b:zstat 2>/dev/null || return 0
  local -A source_stat
  zstat -F '%s.%N' -H source_stat "$source" 2>/dev/null || return 0
  local identity="${source_stat[device]}.${source_stat[inode]}.${source_stat[mtime]}.${source_stat[ctime]}.${source_stat[size]}"
  local cache_dir="$cache_base/$identity"
  local bytecode="$cache_dir/_git.zwc"

  if [[ -s "$bytecode" ]]; then
    fpath=("$cache_dir" "$fpath[@]")
    return 0
  fi

  (
    umask 077
    command mkdir -p -- "$cache_base" || exit 1
    command chmod 700 "$cache_root" "$cache_base" || exit 1

    # Only publishers lock. Readers use immutable generation directories, so
    # they can never observe bytecode from a different source generation.
    local lock_file="$cache_root/.publish.lock"
    : >>"$lock_file" || exit 1
    zmodload -F zsh/system b:zsystem 2>/dev/null || exit 1
    local lock_fd
    zsystem flock -f lock_fd -t 0 "$lock_file" 2>/dev/null || exit 1

    local -A locked_stat
    zstat -F '%s.%N' -H locked_stat "$source" 2>/dev/null || exit 1
    local locked_identity="${locked_stat[device]}.${locked_stat[inode]}.${locked_stat[mtime]}.${locked_stat[ctime]}.${locked_stat[size]}"
    [[ "$locked_identity" == "$identity" ]] || exit 1
    [[ ! -s "$bytecode" ]] || exit 0

    local old_dir
    for old_dir in "$cache_base"/.git-completion.*(N/); do
      command rm -rf -- "$old_dir"
    done

    local suffix="$$.$RANDOM"
    local tmp_dir="$cache_base/.git-completion.$suffix"
    local tmp_bytecode="$tmp_dir/_git.zwc"
    command mkdir -- "$tmp_dir" || exit 1
    trap 'command rm -rf -- "$tmp_dir"' EXIT HUP INT TERM

    zcompile -U "$tmp_bytecode" "$source" || exit 1
    [[ -s "$tmp_bytecode" ]] || exit 1

    # Do not publish bytecode compiled while its source was being replaced.
    local -A current_stat
    zstat -F '%s.%N' -H current_stat "$source" 2>/dev/null || exit 1
    local current_identity="${current_stat[device]}.${current_stat[inode]}.${current_stat[mtime]}.${current_stat[ctime]}.${current_stat[size]}"
    [[ "$current_identity" == "$identity" ]] || exit 1

    [[ ! -e "$cache_dir" ]] || command rm -rf -- "$cache_dir"
    command mv -- "$tmp_dir" "$cache_dir" || exit 1

    # Retain only the active generation. A shell still pointing at an older
    # one safely falls through to the original source if it has not loaded yet.
    for old_dir in "$cache_base"/*(N/); do
      [[ "$old_dir" == "$cache_dir" ]] || command rm -rf -- "$old_dir"
    done

    # Keep a small bound that accommodates system, package-manager, and upgrade
    # Zsh versions without making alternating shells recompile each other.
    local version_dir version_count=0
    for version_dir in "$cache_root"/*(N/om); do
      ((++version_count <= 3)) || command rm -rf -- "$version_dir"
    done
  ) 2>/dev/null || return 0

  # A failed or interrupted refresh leaves the system source first in fpath.
  [[ -s "$bytecode" ]] && fpath=("$cache_dir" "$fpath[@]")
}

_cache_zsh_git_completion
unfunction _cache_zsh_git_completion

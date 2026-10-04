# shellcheck shell=bash
# dot doctor: Cron checks.
#
# Core already reports whether the last cron `dot update` succeeded. This
# section checks what cron will actually run: the managed block in the user
# crontab must match what the cron merge hook renders for this host now, and
# a crontab-wide SHELL= must name an executable, because cron runs every job
# through it.

# Print what the cron merge hook would do for this host: its block marker
# on the first line, then `none` when there is no tracked source at all (the
# hook then leaves the crontab alone) or `block`, followed by the managed
# block it would install (nothing when no tracked entry applies here). Fails
# when the hook runtime or the hook cannot load. Runs the real hook renderer
# in a subshell; its warnings (for example an over-long PATH) belong to
# `dot update`, so stderr is dropped here.
_dr_cron_expected_block() {
  local hook=$DOT_EXTENSIONS_DIR/merge-hooks.d/cron.sh

  [[ -r $hook ]] || return 1
  (
    _dr_hook_runtime_source || exit 1
    # shellcheck source=/dev/null
    . "$hook" || exit 1
    local -a _cron_sources
    _cron_source_files
    if ((${#_cron_sources[@]} == 0)); then
      printf '%s\nnone\n' "$_CRON_MARKER"
      exit 0
    fi
    _cron_render_block
    printf '%s\nblock\n%s' "$_CRON_MARKER" "$REPLY"
  ) 2>/dev/null
}

# Check every crontab-wide SHELL= line in $1. Cron strips one level of
# quotes and expands nothing, so the value must be an absolute executable.
_dr_cron_check_shell() {
  local line value
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*SHELL[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] || continue
    value=${BASH_REMATCH[1]}
    case $value in
      \"*\" | \'*\') value=${value:1:${#value}-2} ;;
    esac
    # Display text must stay on one record line.
    value=${value//[$'\t\r']/ }
    if [[ $value != /* ]]; then
      _dr_hint_row fail "cron SHELL is not an absolute path: $value" \
        "cron needs an absolute program path" "fix the SHELL= line, then run 'dot update'"
    elif [[ -x $value && ! -d $value ]]; then
      _dr_ok "cron SHELL is executable" "$(_dr_tilde "$value")"
    else
      _dr_hint_row fail "cron SHELL is not executable: $(_dr_tilde "$value")" \
        "every cron job using it fails" "restore the program or run 'dot update'"
    fi
  done <<<"$1"
}

# PATH cron gives a job when the crontab sets none (cronie, Vixie, and
# macOS cron agree).
_DR_CRON_DEFAULT_PATH=/usr/bin:/bin

# Report via REPLY the program a crontab job line runs, or fail when there
# is nothing to judge without running a shell: the line is not a job, or
# its command starts with something the shell expands, a builtin, or a
# keyword. Leading NAME=value assignments are skipped; a HOME-relative or
# relative program is made absolute, as cron starts jobs in HOME.
_dr_cron_job_program() {
  local -a words=()
  read -r -a words <<<"$1"
  ((${#words[@]} > 0)) || return 1
  case ${words[0]} in
    '#'*) return 1 ;;
    @*) words=("${words[@]:1}") ;;
    *) words=("${words[@]:5}") ;;
  esac
  while ((${#words[@]} > 0)) && [[ ${words[0]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    words=("${words[@]:1}")
  done
  ((${#words[@]} > 0)) || return 1
  REPLY=${words[0]}
  # shellcheck disable=SC2088 # A literal tilde prefix, expanded here.
  [[ $REPLY != '~/'* ]] || REPLY=$HOME/${REPLY#'~/'}
  case $REPLY in
    *[\$\`\"\'\\\(\)\{\}\;\&\|\<\>\*\?\[\]%~=]*) return 1 ;;
  esac
  case $(type -t -- "$REPLY" 2>/dev/null || true) in
    builtin | keyword) return 1 ;;
  esac
  [[ $REPLY == /* || $REPLY != */* ]] || REPLY=$HOME/$REPLY
}

# Check that every job in the managed block of crontab $1 (marker $2) names
# a program cron can start: a path must be an executable file, and a bare
# name must resolve on the PATH cron gives the job, which is the last PATH=
# line above it (cron applies environment lines in order) or cron's
# default. Stat only. A custom SHELL= that extends PATH itself is not
# modeled, which is why a miss warns rather than fails.
_dr_cron_check_commands() {
  local crontab=$1 marker=$2 line cron_path=$_DR_CRON_DEFAULT_PATH
  local in_block=0 program dir found
  local -a dirs=() missing=()

  while IFS= read -r line; do
    if [[ $line == "$marker begin" ]]; then
      in_block=1
      continue
    elif [[ $line == "$marker end" ]]; then
      in_block=0
      continue
    fi
    if [[ $line =~ ^[[:space:]]*PATH[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]]; then
      cron_path=${BASH_REMATCH[1]}
      case $cron_path in
        \"*\" | \'*\') cron_path=${cron_path:1:${#cron_path}-2} ;;
      esac
      continue
    fi
    ((in_block == 1)) || continue
    # Other environment lines name no program.
    [[ ! $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*= ]] || continue
    _dr_cron_job_program "$line" || continue
    program=$REPLY
    if [[ $program == */* ]]; then
      [[ -f $program && -x $program ]] ||
        missing+=("$(_dr_tilde "$program") is not an executable file")
      continue
    fi
    found=0
    # The extra colon keeps a trailing empty entry (the job's directory,
    # HOME), which read would otherwise drop.
    IFS=: read -r -a dirs <<<"$cron_path:"
    for dir in "${dirs[@]}"; do
      [[ $dir == /* ]] || dir=$HOME/$dir
      if [[ -f $dir/$program && -x $dir/$program ]]; then
        found=1
        break
      fi
    done
    ((found == 1)) || missing+=("$program is not on the job's PATH")
  done <<<"$crontab"

  ((${#missing[@]} > 0)) || return 0
  _dr_list_row warn "${#missing[@]} managed cron job(s) cannot start" \
    "install the program or fix its entry under $(_dr_tilde "$(_merge_hook_family cron/cron.d)"), then run 'dot update'" \
    "${missing[@]}"
}

_dr_check_cron() {
  _dr_section "Cron"

  if [[ ! -d "$(_merge_hook_family cron/cron.d)" ]]; then
    _dr_skip "no tracked cron entries to check"
    return 0
  fi

  local crontab_out crontab_command expected='' marker='' mode='' log
  log=${XDG_STATE_HOME:-$HOME/.local/state}/dot/update.log
  if expected=$(_dr_cron_expected_block); then
    marker=${expected%%$'\n'*}
    expected=${expected#*$'\n'}
    mode=${expected%%$'\n'*}
    expected=${expected#"$mode"}
    expected=${expected#$'\n'}
  fi

  # The merge hook quietly does nothing without crontab, so tracked jobs
  # that apply here would never run; say so instead of skipping.
  if [[ "${DOT_TEST:-0}" != 1 ]] && ! command -v crontab >/dev/null 2>&1; then
    if [[ -n $expected || -z $marker ]]; then
      _dr_hint_row warn "crontab not found" \
        "tracked cron entries cannot be installed" "install cron, then run 'dot update'"
    else
      _dr_skip "crontab not found" "no tracked cron entry applies to this host"
    fi
    return 0
  fi
  _dr_account_scoped_command \
    "Cron" crontab "${DOT_TEST_CRONTAB:-}" || return 0
  crontab_command="$REPLY"
  crontab_out=$("$crontab_command" -l 2>/dev/null || echo "")

  if [[ -z $marker || -z $mode ]]; then
    _dr_skip "managed cron block unchecked" "the cron merge hook could not load"
  elif [[ -z $expected ]]; then
    if [[ $crontab_out != *"$marker begin"* ]]; then
      _dr_ok "no tracked cron entries apply to this host"
    elif [[ $mode == none ]]; then
      # With no tracked source at all the hook leaves the crontab alone.
      _dr_hint_row warn "managed cron block is stale" \
        "no tracked cron source remains, and dot update keeps the old block" "remove it with 'crontab -e'"
    else
      _dr_hint_row warn "managed cron block is stale" \
        "no tracked entry applies to this host any more" "run 'dot update' to remove it"
    fi
  elif [[ $crontab_out == *"$expected"* ]]; then
    _dr_ok "managed cron block is current"
  elif [[ $crontab_out == *"$marker begin"* ]]; then
    _dr_hint_row warn "managed cron block is stale" "it differs from the tracked entries" \
      "run 'dot update', and check $(_dr_tilde "$log") if cron updates keep failing"
  else
    _dr_hint_row warn "managed cron block missing" "tracked entries are not installed" \
      "run 'dot update', and check $(_dr_tilde "$log") if cron updates keep failing"
  fi

  _dr_cron_check_shell "$crontab_out"
  # Judge what cron runs now, the installed block, rather than what the
  # next update would install; a stale block already has its own row.
  [[ -z $marker ]] || _dr_cron_check_commands "$crontab_out" "$marker"
}

# shellcheck shell=bash
# dot doctor: Tools checks.
#
# Core reports the Git and Bash runtimes and the dependency provider itself;
# this section covers what base adds on top: the health of everything shdeps
# installed. The shdeps configuration is tracked files, whose drift core's
# repository rows already report.

dot_doctor_source doctor.d/lib/shdeps-links.sh || return

# Render one `shdeps health` row as a list item: package and kind, the path
# when there is one, then shdeps' own detail, which names the cause and the
# fix. `-` marks an absent column. A detail that already names the path
# (an older shdeps repeated a transition record's path there) leaves the
# path column out, so the item never prints it twice.
_dr_shdeps_health_item() {
  local package=$1 kind=$2 path=$3 detail=$4 item='' padded
  [[ -z $package || $package == - ]] || item="$package: "
  item+=$kind
  # The path counts as named only as a whole word: bounded by the start or
  # end, a blank, `;`, `,`, a parenthesis, or a sentence's final `.`, so a
  # different path that merely starts or ends with it keeps the column.
  padded=" ${detail//[;,()]/ } "
  padded=${padded//. / }
  [[ -z $path || $path == - || $padded == *" $path "* ]] ||
    item+=" $(_dr_tilde "$path")"
  [[ -z $detail || $detail == - ]] || item+=" — $detail"
  REPLY=$item
}

# Render `shdeps health` as one row: ok when healthy, otherwise the worst
# severity it reported, with every problem listed fail rows first, so a
# failure is never folded behind warnings. Only the severity column drives
# the verdict: `fail` fails the row, and any other value, including one a
# newer shdeps adds, counts as a warning. The other columns are display
# text, so an unknown kind renders like any other.
_dr_check_shdeps_health() {
  local severity package kind path detail level=warn message hint
  local -a failing=() others=()

  case $_DR_SHDEPS_HEALTH_STATUS in
    0)
      _dr_ok "shdeps health" "installed dependencies, links, and state are consistent"
      return 0
      ;;
    error-124 | error-137)
      _dr_hint_row fail "shdeps health timed out" "" "run 'shdeps health' to see where it stalls"
      return 0
      ;;
    error-*)
      _dr_hint_row fail "shdeps health failed (exit ${_DR_SHDEPS_HEALTH_STATUS#error-})" "" \
        "run 'shdeps health' to see the error"
      return 0
      ;;
  esac

  while IFS=$'\t' read -r severity package kind path detail; do
    [[ -n $severity ]] || continue
    _dr_shdeps_health_item "$package" "$kind" "$path" "$detail"
    if [[ $severity == fail ]]; then
      failing+=("$REPLY")
    else
      others+=("$REPLY")
    fi
  done <<<"$_DR_SHDEPS_HEALTH_OUTPUT"

  if ((${#failing[@]} + ${#others[@]} == 0)); then
    _dr_hint_row fail "shdeps health report incomplete" "" \
      "run 'shdeps health' to see what it could not read"
    return 0
  fi
  message="shdeps health: $((${#failing[@]} + ${#others[@]})) problem(s)"
  hint="follow the fix on each line; 'shdeps health' lists them all"
  if ((${#failing[@]} > 0)); then
    level=fail
    ((${#others[@]} == 0)) || message+=", ${#failing[@]} failing"
  fi
  # An incomplete report fails even when every row it managed to print was
  # a warning: the unread state may hide anything.
  if [[ $_DR_SHDEPS_HEALTH_STATUS == 3 ]]; then
    level=fail
    hint="some shdeps state could not be read, so more may be wrong; $hint"
  fi
  _dr_list_row "$level" "$message" "$hint" \
    ${failing[@]+"${failing[@]}"} ${others[@]+"${others[@]}"}
}

_dr_check_tools() {
  _dr_section "Tools"

  if _dr_shdeps_health_probe; then
    # One stat-only pass covers every installed package's command links
    # plus deferred, recovery, transition, and install-root state.
    _dr_check_shdeps_health
  elif ! command -v shdeps >/dev/null 2>&1; then
    _dr_hint_row warn "shdeps health unchecked" "shdeps is not on PATH" "run 'dot update'"
  else
    # Every supported shdeps has `health`; one that rejects or cannot run
    # it is out of date or broken, and `dot update` replaces it.
    _dr_hint_row warn "shdeps health unchecked" \
      "the installed shdeps cannot run 'shdeps health'" "run 'dot update' to upgrade it"
  fi
}

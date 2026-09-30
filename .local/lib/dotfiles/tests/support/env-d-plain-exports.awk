# env-d-plain-exports.awk — list env.d lines that export a name directly.
#
# env.d fragments must export dotfiles-owned values with _shell_env_set (see
# ~/.config/shell/README.md, Environment Ownership): a plain export overwrites
# a caller's value in fill-only shells and looks inherited to later fragments.
# Prints `file:line: text` for each line with an `export`, `declare -x`, or
# `typeset -x` of a name that is neither in the space-separated `allow` list
# (awk -v allow="PATH MANPATH") nor assigned in the `${NAME:-default}` form,
# which yields to an existing value in every mode. A bare `export NAME` counts
# too, since it exports whatever an earlier plain assignment set.
#
# A line-based heuristic, not a shell parser: it skips comment lines and
# trailing ` #` comments, and understands quoted values, but it does not
# see through strings that merely contain the word export or through
# continuation lines. Shared by the base and overlay suites.

BEGIN {
  n = split(allow, allowed_list, /[[:space:]]+/)
  for (i = 1; i <= n; i++) allowed[allowed_list[i]] = 1
}

# Return the text after one shell word value (quotes honored).
function skip_value(s, c, q) {
  q = ""
  while (s != "") {
    c = substr(s, 1, 1)
    if (q == "") {
      if (c ~ /[[:space:];&|)]/) break
      if (c == "\"" || c == "'") q = c
      else if (c == "\\") s = substr(s, 2)
    } else if (c == q) {
      q = ""
    } else if (q == "\"" && c == "\\") {
      s = substr(s, 2)
    }
    s = substr(s, 2)
  }
  return s
}

function fill_form(name, value) {
  return value ~ ("^\"?\\$\\{" name ":?[-=]")
}

/^[[:space:]]*#/ { next }

{
  line = $0
  sub(/[[:space:]]#.*$/, "", line)
  bad = 0
  while (!bad && match(line, /(^|[;&|({[:space:]])(export|(declare|typeset)[[:space:]]+-[A-Za-z]*x[A-Za-z]*)([[:space:]]+|$)/)) {
    rest = substr(line, RSTART + RLENGTH)
    # Options: -n/-f (unexport, functions) are not value exports.
    skip = 0
    while (match(rest, /^-[A-Za-z]+[[:space:]]*/)) {
      if (substr(rest, 1, RLENGTH) ~ /[nf]/) skip = 1
      rest = substr(rest, RLENGTH + 1)
    }
    while (!skip && match(rest, /^"?[A-Za-z_][A-Za-z0-9_]*/)) {
      quoted = substr(rest, 1, 1) == "\""
      name = substr(rest, 1 + quoted, RLENGTH - quoted)
      rest = substr(rest, RLENGTH + 1)
      if (substr(rest, 1, 1) == "=") {
        value = substr(rest, 2)
        if (quoted) value = "\"" value
        if (!(name in allowed) && !fill_form(name, value)) bad = 1
        rest = skip_value(substr(rest, 2))
      } else {
        if (!(name in allowed)) bad = 1
        if (quoted && substr(rest, 1, 1) == "\"") rest = substr(rest, 2)
      }
      if (bad) break
      sub(/^[[:space:]]+/, "", rest)
    }
    line = rest
  }
  if (bad) printf "%s:%d: %s\n", FILENAME, FNR, $0
}

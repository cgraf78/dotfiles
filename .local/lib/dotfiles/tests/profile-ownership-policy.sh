#!/usr/bin/env bash
# Shared parser for the steady-state public profile ownership policy.

dot_profile_ownership_policy_validate() {
  local policy=$1
  awk -F '\t' '
    NR == 1 {
      if ($0 != "owners\tfamily\tpathspec") {
        print "invalid profile ownership policy header" > "/dev/stderr"
        bad = 1
      }
      next
    }
    NF != 3 {
      print "invalid profile ownership policy row " NR > "/dev/stderr"
      bad = 1
      next
    }
    $1 !~ /^(base|editor|dev|local|base,editor|base,dev|editor,dev|base,editor,dev)$/ {
      print "invalid profile ownership owners on row " NR > "/dev/stderr"
      bad = 1
    }
    $2 !~ /^[a-z0-9][a-z0-9-]*$/ {
      print "invalid profile ownership family on row " NR > "/dev/stderr"
      bad = 1
    }
    $3 !~ /^\./ || $3 ~ /(^|\/)\.\.?(\/|$)/ || $3 ~ /[[:space:]]/ {
      print "invalid profile ownership pathspec on row " NR > "/dev/stderr"
      bad = 1
    }
    seen[$3]++ {
      print "duplicate profile ownership pathspec on row " NR > "/dev/stderr"
      bad = 1
    }
    family_owners[$2] && family_owners[$2] != $1 {
      print "profile ownership family has multiple owner sets on row " NR > "/dev/stderr"
      bad = 1
    }
    { family_owners[$2] = $1 }
    END {
      if (NR < 2) {
        print "empty profile ownership policy" > "/dev/stderr"
        bad = 1
      }
      exit bad
    }
  ' "$policy"
}

dot_profile_ownership_forbidden() {
  local policy=$1 owner=$2 prefix=${3:-}
  awk -F '\t' -v owner="$owner" -v prefix="$prefix" '
    NR > 1 && index("," $1 ",", "," owner ",") == 0 {
      print prefix $3
    }
  ' "$policy"
}

dot_profile_ownership_owned() {
  local policy=$1 owner=$2 prefix=${3:-}
  awk -F '\t' -v owner="$owner" -v prefix="$prefix" '
    NR > 1 && index("," $1 ",", "," owner ",") != 0 {
      print $2 "\t" prefix $3
    }
  ' "$policy"
}

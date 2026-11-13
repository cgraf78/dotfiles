# clip clean: undo the layout an agent TUI (Claude Code, Codex, Muse) adds to
# its transcript, so a selection copied from the pane reads as the text the
# agent wrote.
#
# The TUIs wrap text themselves at the pane width and indent each continuation
# under the text it continues, so tmux sees hard line breaks it cannot undo.
# This filter rejoins a row with the next one only when that row is a plausible
# wrap: the next row continues at the same indentation and its first word could
# not have fit in the space left on the row. It also turns the transcript's
# message markers (●, ⏺, •, ❯, ›, ↳, ✻), tool-output markers (⎿, └) and a
# left gutter shared by every line (│, ▌, ▎, ┃) into indentation, then removes
# the indentation common to the selection.
#
# Structure is kept: blank lines, list items, headings, quotes, fences, box
# drawing and tables, shell prompts, rows wider than the pane (which tmux had
# already soft-wrapped and rejoined) and rows that begin at the left margin.
#
# Run with LC_ALL=C so every awk counts bytes; the filter decodes UTF-8 itself
# to measure display width. Variables:
#   width          pane width in columns (required)
#   column         display column where the first line starts (default 0)
#   final_newline  1 when the input ends with a newline (default 0)

BEGIN {
  if (width !~ /^[1-9][0-9]*$/) {
    print "clip clean: width must be a positive integer" > "/dev/stderr"
    invalid = 1
    exit 2
  }
  width += 0
  column += 0
  # The filter measures bytes. An awk that counts characters even under
  # LC_ALL=C (such as a UTF-8 one-true-awk) fails here, and clip then copies
  # the selection as captured.
  if (length(sprintf("%c", 200)) != 1 || length("é") != 2) {
    print "clip clean: this awk does not count bytes" > "/dev/stderr"
    invalid = 1
    exit 2
  }
  for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
  # ASCII rows skip decoding. A regex library that cannot match a byte range
  # (some C locales) decodes every row instead, which is only slower.
  HIGH = "[" sprintf("%c", 128) "-" sprintf("%c", 255) "]"
  if (sprintf("%c", 200) !~ HIGH || "a" ~ HIGH) HIGH = ""
  # Message markers open a transcript entry at the left margin. A reply is
  # rendered markdown, whose wrapped rows continue under the text of their
  # list item. A prompt echo (Codex ›, Claude ❯) is the user's raw text,
  # wrapped one column narrower than the pane with its continuations at the
  # margin. Until a selection shows a marker, either may be under way.
  # Claude's older > echo is left out: it is also the shell's PS2 prompt.
  nmarks = split("● ⏺ • ↳ ✻ › ❯", MARK, " ")
  ECHO["›"] = 1
  ECHO["❯"] = 1
  nlines = 0
}

{ raw[++nlines] = $0 }

END {
  if (invalid) exit 2
  if (nlines == 0) exit
  gutter = has_gutter()
  ew = width
  kind = 0
  intool = 0
  for (i = 1; i <= nlines; i++) {
    t = raw[i]
    sub(/[ \t]+$/, "", t)
    # Widths are those of the screen row, before any marker is replaced.
    w[i] = strw(t) + (i == 1 && column > 0 ? column : 0)
    mk[i] = 0
    if (gutter) t = ungutter(t)
    for (m = 1; m <= nmarks; m++) {
      if (substr(t, 1, length(MARK[m]) + 1) == MARK[m] " ") {
        t = "  " substr(t, length(MARK[m]) + 2)
        mk[i] = 1
        intool = 0
        kind = (MARK[m] in ECHO) ? 2 : 1
        ew = (kind == 2) ? width - 1 : width
        break
      }
    }
    tool[i] = 0
    if (match(t, /^ +(⎿|└) /)) {
      pre = substr(t, 1, RLENGTH - 1)
      sub(/(⎿|└)$/, " ", pre)
      t = pre substr(t, RLENGTH)
      tool[i] = 1
      intool = 1
    }
    # Codex draws a markdown bullet as •; give it back its markdown form. At
    # the margin, • opens a Codex message instead (handled above).
    if (match(t, /^ +• /)) t = substr(t, 1, RLENGTH - 4) "- " substr(t, RLENGTH + 1)
    eff[i] = ew
    # 0 before any marker, 1 in a reply, 2 in a prompt echo.
    block[i] = kind
    text[i] = t
    blank[i] = (t ~ /^[ \t]*$/)
    if (blank[i]) intool = 0
    output[i] = intool
    ind[i] = blank[i] ? 0 : match(t, /[^ ]/) - 1
    body[i] = substr(t, ind[i] + 1)
    cind[i] = ind[i]
    if (match(body[i], /^([-*+]|[0-9]+[.)]) +/)) cind[i] = ind[i] + RLENGTH
  }

  # A first line that starts mid-row, which tmux reports as its column, has
  # unknown indentation: it neither sets the margin nor constrains how its
  # continuation is indented.
  mid = (column > 0 && !blank[1] && !mk[1])
  base = -1
  for (i = mid ? 2 : 1; i <= nlines; i++)
    if (!blank[i] && (base < 0 || ind[i] < base)) base = ind[i]
  if (base < 0) base = 0

  out = 0
  for (i = 1; i <= nlines; i++) {
    if (i > 1 && joins(i - 1, i)) {
      sep = joiner(i - 1, i)
      sub(/[ \t]+$/, "", line[out])
      line[out] = line[out] sep body[i]
      if (cont < 0) cont = ind[i]
      continue
    }
    line[++out] = text[i]
    start = i
    cont = -1
  }

  for (k = 1; k <= out; k++) {
    s = line[k]
    if (s ~ /^[ \t]*$/) s = ""
    else {
      for (d = 0; d < base && substr(s, 1, 1) == " "; d++) s = substr(s, 2)
    }
    printf "%s%s", s, (k < out || final_newline) ? "\n" : ""
  }
}

# Decide whether row b continues row a.
function joins(a, b,    sep) {
  # Agent rows keep a margin of at least two columns; shell output and the
  # context lines of a diff start further left.
  if (blank[a] || blank[b] || ind[b] < 2) return 0
  # A row wider than the pane was soft-wrapped by tmux and is already whole.
  if (w[a] > eff[a]) return 0
  # Tool output is records (log lines, git log, test results) whose length
  # says nothing; only a row filled to the edge can have been wrapped.
  if (output[a] && w[a] < eff[a] - 1) return 0
  if (ends_block(a) || starts_block(b)) return 0
  if (cont >= 0) {
    if (ind[b] != cont) return 0
  } else if (!(start == 1 && mid)) {
    # A reply continues under the item's text, an echo at the margin. Text
    # with no marker may be either, so it also accepts the margin, but only
    # under a row that itself starts there.
    if (ind[b] != cind[start] &&
        (block[start] == 1 ||
         (ind[b] != base && (block[start] == 0 || ind[b] != ind[start])) ||
         (block[start] == 0 && ind[start] != base))) return 0
  }
  if (a == start && !(a == 1 && mid) && parallel(body[a], body[b])) return 0
  unit(body[b])
  sep = (UCJK || cjk(lastcp(body[a])) || breaks_after(body[a])) ? 0 : 1
  return w[a] + sep + UW > eff[a]
}

# Rows that open alike, digits aside, are records of one kind, such as log
# lines, test results or a process list, rather than a wrapped sentence. A
# plain lowercase word could open both halves of wrapped prose, so it must be
# followed by a second matching word.
function parallel(s, t,    n) {
  gsub(/[0-9]/, "9", s)
  gsub(/[0-9]/, "9", t)
  n = (s ~ /^[a-z]+ /) ? 2 : 1
  s = lead(s, n)
  return length(s) >= 3 && s == lead(t, n)
}

function lead(s, n,    i, r) {
  r = ""
  for (i = 1; i <= n; i++) {
    if (!match(s, /^[^ ]+/)) return ""
    r = r " " substr(s, 1, RLENGTH)
    s = substr(s, RLENGTH + 1)
    sub(/^ +/, "", s)
  }
  return r
}

# Text inserted between the two halves of a rejoined row.
function joiner(a, b,    last, nextcp, tok) {
  last = lastcp(body[a])
  decode(body[b], 1)
  nextcp = CP
  if (cjk(last) && cjk(nextcp)) return ""
  if (breaks_after(body[a])) return ""
  # A wide character that did not fit leaves the last column empty.
  if ((cjk(last) || cjk(nextcp)) && w[a] >= eff[a] - 1) return ""
  # A row filled to the edge whose last token is part of a URL, path or
  # identifier was broken inside it. A word wrap leaves the row shorter, or
  # ends it with a whole word, which may well precede a path.
  if (w[a] < eff[a]) return " "
  tok = body[a]
  sub(/.* /, "", tok)
  if (tok ~ /[\/\\_=&?#%~@]/ || (length(tok) >= 6 && tok ~ /[A-Za-z0-9][.:][a-z0-9]/))
    return ""
  return " "
}

# Codex also wraps after a hyphen or slash inside a word.
function breaks_after(s) {
  return s ~ /[A-Za-z0-9][-\/]$/
}

function ends_block(a,    s) {
  s = body[a]
  if (s ~ /^(```|~~~)/ || s ~ /^\|.*\|$/) return 1
  # The TUIs end a row they truncated, rather than wrapped, with an ellipsis.
  # Code opening a block or continuing a shell line ends with its own break.
  if (s ~ /(…|[{\\])$/) return 1
  return boxy(s, 1) || boxy(s, length(s) - lastlen(s) + 1)
}

function starts_block(b,    s) {
  if (mk[b] || tool[b]) return 1
  s = body[b]
  # After a line of code, a call or an assignment opens the next statement.
  # After a plain word it is inline code continuing a sentence.
  if (s ~ /^[A-Za-z_][A-Za-z0-9_.]*[(=]/ && body[b - 1] !~ /(^| )[A-Za-z]+[,;:]?$/)
    return 1
  if (s ~ /^([-*+]|[0-9]+[.)]) /) return 1
  if (s ~ /^(```|~~~|\||#+ |> |[$%] )/) return 1
  return boxy(s, 1)
}

# Box drawing and block elements, U+2500 to U+259F.
function boxy(s, j) {
  decode(s, j)
  return CP >= 9472 && CP <= 9631
}

# The left gutter must start every non-blank line, and no line may hold other
# box drawing, which would make it a table rather than a gutter.
function has_gutter(    i, t, rest, j, n) {
  n = 0
  for (i = 1; i <= nlines; i++) {
    t = raw[i]
    if (t ~ /^[ \t]*$/) continue
    if (!match(t, /^ *(│|▌|▎|┃)( |$)/)) return 0
    rest = substr(t, RLENGTH + 1)
    for (j = 1; j <= length(rest); j += CL) {
      decode(rest, j)
      if (CP >= 9472 && CP <= 9631) return 0
    }
    n++
  }
  return n > 0
}

function ungutter(t,    pre) {
  match(t, /^ *(│|▌|▎|┃)/)
  pre = substr(t, 1, RLENGTH)
  sub(/(│|▌|▎|┃)$/, " ", pre)
  return pre substr(t, RLENGTH + 1)
}

# The leading word of s, which the wrap could not fit: a CJK character stands
# alone, as every one is a break opportunity. Sets UW (width) and UCJK.
function unit(s,    j, n, c) {
  UW = 0
  UCJK = 0
  n = length(s)
  for (j = 1; j <= n; j += CL) {
    decode(s, j)
    c = CP
    if (c == 32) break
    if (cjk(c)) {
      if (j == 1) {
        UW = 2
        UCJK = 1
      }
      break
    }
    UW += cpw(c)
  }
}

function lastlen(s,    j, b) {
  for (j = length(s); j > 1; j--) {
    b = ORD[substr(s, j, 1)]
    if (b < 128 || b >= 192) break
  }
  return length(s) - j + 1
}

function lastcp(s) {
  if (s == "") return 0
  decode(s, length(s) - lastlen(s) + 1)
  return CP
}

# Decode the UTF-8 character at byte j of s into CP, with byte length CL.
function decode(s, j,    b, n, k, c) {
  b = ORD[substr(s, j, 1)]
  CL = 1
  if (b < 192) {
    CP = (b < 128) ? b : 65533
    return
  }
  if (b >= 240) { n = 3; c = b - 240 }
  else if (b >= 224) { n = 2; c = b - 224 }
  else { n = 1; c = b - 192 }
  for (k = 1; k <= n; k++) {
    b = ORD[substr(s, j + k, 1)]
    if (b < 128 || b >= 192) {
      CP = 65533
      return
    }
    c = c * 64 + b - 128
  }
  CP = c
  CL = n + 1
}

function strw(s,    j, n, total, joined) {
  if (HIGH != "" && s !~ HIGH) return length(s)
  total = 0
  n = length(s)
  joined = 0
  for (j = 1; j <= n; j += CL) {
    decode(s, j)
    # An emoji joined to the one before it (ZWJ) shares its cell.
    if (!joined) total += cpw(CP)
    joined = (CP == 8205)
  }
  return total
}

# Display width of a code point, as terminals render it.
function cpw(c) {
  if (c < 768) return 1
  if ((c >= 768 && c <= 879) || (c >= 6832 && c <= 6911) || (c >= 7616 && c <= 7679) ||
      (c >= 8203 && c <= 8207) || (c >= 8288 && c <= 8292) || (c >= 8400 && c <= 8447) ||
      (c >= 65024 && c <= 65039) || (c >= 65056 && c <= 65071) ||
      (c >= 127995 && c <= 127999) || (c >= 917760 && c <= 917999)) return 0
  if (c < 4352) return 1
  if (c <= 4447 || cjk(c) || (c >= 44032 && c <= 55203) || (c >= 65072 && c <= 65103) ||
      (c >= 65504 && c <= 65510) || (c >= 127744 && c <= 128591) ||
      (c >= 128640 && c <= 128767) || (c >= 129280 && c <= 129535) ||
      (c >= 129648 && c <= 129791) || (c >= 128992 && c <= 129003) ||
      (c >= 126980 && c <= 127569 && wide_symbol(c)) ||
      (c >= 8986 && c <= 11093 && wide_symbol(c))) return 2
  return 1
}

# Emoji in blocks that are mostly narrow, which Unicode gives East Asian
# width W.
function wide_symbol(c) {
  return c == 8986 || c == 8987 || (c >= 9193 && c <= 9196) || c == 9200 ||
    c == 9203 || c == 9725 || c == 9726 || c == 9748 || c == 9749 ||
    (c >= 9800 && c <= 9811) || c == 9855 || c == 9875 || c == 9889 ||
    c == 9898 || c == 9899 || c == 9917 || c == 9918 || c == 9924 || c == 9925 ||
    c == 9934 || c == 9940 || c == 9962 || c == 9970 || c == 9971 || c == 9973 ||
    c == 9978 || c == 9981 || c == 9989 || c == 9994 || c == 9995 ||
    c == 10024 || c == 10060 || c == 10062 || (c >= 10067 && c <= 10069) ||
    c == 10071 || (c >= 10133 && c <= 10135) || c == 10160 || c == 10175 ||
    c == 11035 || c == 11036 || c == 11088 || c == 11093 ||
    c == 126980 || c == 127183 || c == 127374 || (c >= 127377 && c <= 127386) ||
    (c >= 127488 && c <= 127490) || (c >= 127504 && c <= 127547) ||
    (c >= 127552 && c <= 127560) || c == 127568 || c == 127569
}

# Scripts written without spaces between words, where a wrap may fall between
# any two characters: CJK punctuation, kana, ideographs and fullwidth forms.
function cjk(c) {
  return (c >= 11904 && c <= 12350) || (c >= 12353 && c <= 19903) ||
    (c >= 19968 && c <= 40959) || (c >= 63744 && c <= 64255) ||
    (c >= 65280 && c <= 65376) || (c >= 131072 && c <= 262141)
}

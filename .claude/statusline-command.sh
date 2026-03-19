#!/usr/bin/env bash
# Claude Code status line.
# Format: hostname | path (branch flags) | 🤖 model | 🧠 ctx% | 💰 $cost | 💬 N turns

export LC_NUMERIC=C
input=$(cat)

# ANSI colors
BOLD_CYAN='\033[1;36m'
GREEN='\033[0;32m'
BRIGHT_GREEN='\033[1;32m'
YELLOW='\033[0;33m'
ORANGE='\033[38;5;208m'
MAGENTA='\033[0;35m'
RED='\033[0;31m'
FAST_ORANGE='\033[38;2;255;120;20m'
RESET='\033[0m'

# Extract values
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model_id=$(printf '%s' "$input" | jq -r '.model.id // empty')
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
total_cost=$(printf '%s' "$input" | jq -r '.cost.total_cost_usd // empty')
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')

# Short model name (strip claude- prefix and date suffix)
model=""
if [ -n "$model_id" ]; then
    model=$(echo "$model_id" | sed -E '
        s/^claude-//
        s/-[0-9]{8}$//
        s/^([0-9]+)-([0-9]+)-(.+)$/\3-\1.\2/
        s/^([0-9]+)-([^0-9].*)$/\2-\1/
        s/^([^0-9].*)-([0-9]+)-([0-9]+)$/\1-\2.\3/
    ')
fi

# Fast mode
fast_mode=$(jq -r '.fastMode // false' ~/.claude/settings.json 2>/dev/null)

# Hostname
host=$(hostname -s)

# Directory (replace $HOME with ~)
dir="?"
if [ -n "$cwd" ]; then
    dir="${cwd/#$HOME/\~}"
fi

# Git branch + dirty flags
branch_part=""
if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    if [ -n "$branch" ]; then
        status=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
        flags=""
        printf '%s' "$status" | grep -qE '^[MADRC]' && flags="${flags}+"
        printf '%s' "$status" | grep -qE '^.[MDRC]' && flags="${flags}*"
        printf '%s' "$status" | grep -q '^??' && flags="${flags}%"
        [ -n "$flags" ] && flags=" $flags"
        branch_part=" (${branch}${flags})"
    fi
fi

# Context percentage with color
ctx_color="$GREEN"
if [ -n "$used" ]; then
    ctx_int=$(printf "%.0f" "$used" 2>/dev/null || echo "0")
    if [ "$ctx_int" -ge 85 ]; then
        ctx_color="$RED"
    elif [ "$ctx_int" -ge 66 ]; then
        ctx_color="$ORANGE"
    elif [ "$ctx_int" -ge 33 ]; then
        ctx_color="$YELLOW"
    fi
fi

# Cost (prefer native total_cost_usd, fall back to token math)
cost_fmt=""
if [ -n "$total_cost" ] && [ "$total_cost" != "null" ] && [ "$total_cost" != "0" ]; then
    cost_fmt=$(printf "%.2f" "$total_cost" 2>/dev/null || echo "0.00")
else
    total_in=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
    total_out=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0')
    cache_write=$(printf '%s' "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
    cache_read=$(printf '%s' "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
    if [ "$total_in" -gt 0 ] 2>/dev/null || [ "$total_out" -gt 0 ] 2>/dev/null; then
        cost_fmt=$(awk -v id="$model_id" \
                       -v tin="$total_in" -v tout="$total_out" \
                       -v cw="$cache_write" -v cr="$cache_read" '
        BEGIN {
            if      (id ~ /opus/)   { pin=15;   pcw=18.75; pcr=1.50; pout=75  }
            else if (id ~ /haiku/)  { pin=0.80; pcw=1;     pcr=0.08; pout=4   }
            else                    { pin=3;    pcw=3.75;  pcr=0.30; pout=15  }
            cost = (tin * pin + cw * pcw + cr * pcr + tout * pout) / 1000000
            printf "%.2f", cost
        }')
    fi
fi

# Turn count from transcript
turn_count=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    turn_count=$(jq -s '
      [.[] | select(.type == "user")] |
      map(select(
        (.message.content | type) == "string" and
        (.message.content | startswith("<local-command") | not) and
        (.message.content | startswith("<command-name>") | not)
      )) | length
    ' "$transcript" 2>/dev/null || echo "0")
fi

# Session name
session_name=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
    session_name=$(grep '^{"type":"custom-title"' "$transcript" 2>/dev/null | tail -1 | jq -r '.customTitle // empty')
fi

# Build status line
LINE=""
SEP=""

LINE="${BOLD_CYAN}${host}${RESET}"
SEP=" | "

LINE="${LINE}${SEP}${GREEN}${dir}${BRIGHT_GREEN}${branch_part}${RESET}"

if [ -n "$session_name" ]; then
    LINE="${LINE}${SEP}${BOLD_CYAN}⚡${session_name}${RESET}"
fi

if [ -n "$model" ]; then
    if [ "$fast_mode" = "true" ]; then
        LINE="${LINE}${SEP}${MAGENTA}🤖 ${model} ${FAST_ORANGE}↯fast${RESET}"
    else
        LINE="${LINE}${SEP}${MAGENTA}🤖 ${model}${RESET}"
    fi
fi

if [ -n "$used" ]; then
    LINE="${LINE}${SEP}${ctx_color}🧠 ${ctx_int}%${RESET}"
fi

if [ -n "$cost_fmt" ]; then
    LINE="${LINE}${SEP}${YELLOW}💰 \$${cost_fmt}${RESET}"
fi

if [ -n "$turn_count" ] && [ "$turn_count" != "0" ]; then
    LINE="${LINE}${SEP}${MAGENTA}💬 ${turn_count} turns${RESET}"
fi

echo -e "$LINE" | tr -d '\r' | head -1

#!/usr/bin/env bash
# Claude Code status line — mirrors the bash PS1 from ~/.bashrc.
# Format: user@host:path (branch flags) | model | ctx% | ~$cost [session]

input=$(cat)

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty')
model_id=$(printf '%s' "$input" | jq -r '.model.id // empty')
used=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
session_name=$(printf '%s' "$input" | jq -r '.session_name // empty')

# Cumulative token counts for cost estimation
total_in=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
total_out=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0')
cache_write=$(printf '%s' "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(printf '%s' "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

# Git branch + dirty flags (skip optional lock to avoid blocking)
git_prompt=""
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
        git_prompt=" ($branch$flags)"
    fi
fi

user=$(whoami)
host=$(hostname -s)

# Shorten cwd: replace $HOME with ~
if [ -n "$cwd" ]; then
    home=$(printf '%s' "$HOME")
    short_cwd="${cwd/#$home/\~}"
else
    short_cwd="?"
fi

# Context percentage suffix
ctx_part=""
if [ -n "$used" ]; then
    ctx_part=" | ${used}% used"
fi

# Model suffix
model_part=""
if [ -n "$model" ]; then
    model_part=" | $model"
fi

# Estimated session cost using per-model pricing ($/MTok).
# Pricing as of 2025-08: opus $15/$18.75/$1.50/$75,
# sonnet $3/$3.75/$0.30/$15, haiku $0.80/$1/$0.08/$4.
# Cache tokens come from current_usage (last call); total_in/out are cumulative.
cost_part=""
if [ "$total_in" -gt 0 ] 2>/dev/null || [ "$total_out" -gt 0 ] 2>/dev/null; then
    cost=$(awk -v id="$model_id" \
               -v tin="$total_in" -v tout="$total_out" \
               -v cw="$cache_write" -v cr="$cache_read" '
    BEGIN {
        if      (id ~ /opus/)   { pin=15;   pcw=18.75; pcr=1.50; pout=75  }
        else if (id ~ /haiku/)  { pin=0.80; pcw=1;     pcr=0.08; pout=4   }
        else                    { pin=3;    pcw=3.75;  pcr=0.30; pout=15  }
        cost = (tin * pin + cw * pcw + cr * pcr + tout * pout) / 1000000
        printf "%.4f", cost
    }')
    cost_part=" | ~\$$cost"
fi

# Session name suffix (only when set)
session_part=""
if [ -n "$session_name" ]; then
    session_part=" [$session_name]"
fi

printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[33m%s\033[00m%s%s%s%s\n' \
    "$user" "$host" "$short_cwd" "$git_prompt" \
    "$model_part" "$ctx_part" "$cost_part" "$session_part"

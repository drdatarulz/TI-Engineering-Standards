#!/usr/bin/env bash
# Claude Code statusLine command
# Mirrors PS1: bold-green user@host : bold-blue cwd, plus model and context info

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Bold green for user@host, reset, colon, bold blue for cwd, reset
printf '\033[01;32m%s@%s\033[00m:\033[01;34m%s\033[00m' \
    "$(whoami)" "$(hostname -s)" "${cwd:-$(pwd)}"

# Model info (dimmed)
if [ -n "$model" ]; then
    printf ' \033[02m[%s]\033[00m' "$model"
fi

# Context usage
if [ -n "$used" ]; then
    printf ' \033[02mctx:%s%%\033[00m' "$used"
fi

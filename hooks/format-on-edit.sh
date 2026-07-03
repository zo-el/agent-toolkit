#!/usr/bin/env bash
# PostToolUse[Write|Edit], async — auto-format the file that was just written
# so formatting never depends on the model remembering to run it. Formatter
# per extension, and only formatters that are actually installed; prettier
# additionally requires a project prettier config so unconfigured repos are
# never reformatted on someone else's defaults.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
fp="$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -n "$fp" ] && [ -f "$fp" ] || exit 0

case "$fp" in
  *.rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt --edition 2021 "$fp" 2>/dev/null
    ;;
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.scss|*.html|*.vue|*.svelte)
    dir="$(dirname "$fp")"
    # nearest package.json/prettier config upward = the project opted in
    probe="$dir"
    conf=""
    while [ "$probe" != "/" ] && [ -z "$conf" ]; do
      for c in .prettierrc .prettierrc.json .prettierrc.yaml .prettierrc.yml .prettierrc.js prettier.config.js prettier.config.mjs; do
        [ -f "$probe/$c" ] && conf="$probe/$c" && break
      done
      [ -z "$conf" ] && [ -f "$probe/package.json" ] \
        && grep -q '"prettier"' "$probe/package.json" 2>/dev/null && conf="$probe/package.json"
      probe="$(dirname "$probe")"
    done
    if [ -n "$conf" ]; then
      bin="$(dirname "$conf")/node_modules/.bin/prettier"
      [ -x "$bin" ] || bin="$(command -v prettier || true)"
      [ -n "$bin" ] && "$bin" --write "$fp" >/dev/null 2>&1
    fi
    ;;
  *.py)
    command -v black >/dev/null 2>&1 && black -q "$fp" 2>/dev/null
    ;;
esac
exit 0

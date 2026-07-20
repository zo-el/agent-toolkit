#!/usr/bin/env bash
# Launcher for any long-lived background process an agent (or the session)
# starts — a dev server, watcher, tail. Registers it so reap-managed.sh can
# clean it up if it is ever left behind; a raw `nohup … &` orphans to init and
# nobody ever cleans it up (verified).
#
#   spawn-managed.sh [--log FILE] -- cmd args…
#
# Ownership is the **owning Claude CLI process** (pid + kernel start time),
# found by walking up to the ancestor that has a ~/.claude/sessions/<pid>.json.
# Not the session id: subagents inherit CLAUDE_CODE_SESSION_ID from the parent,
# and /clear or /resume rotates the id while the process lives — either would
# make ownership lie. A pid+starttime pair is stable across both and is the
# thing that actually dies when the session is over.
#
# Registry JSON is built with jq so a command containing quotes, backslashes,
# or newlines cannot corrupt an entry (a malformed entry reads back as an empty
# pid and gets pruned, orphaning the process for good).
set -uo pipefail

reg="$HOME/.claude/managed-procs"
mkdir -p "$reg"

log=/dev/null
if [ "${1:-}" = "--log" ]; then log="$2"; shift 2; fi
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "usage: spawn-managed.sh [--log FILE] -- cmd args…" >&2; exit 2; }

# Kernel start time (ticks since boot) — makes a pid unambiguous across reuse.
# Strip through the last ')' first: comm can contain spaces and parentheses.
starttime_of() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'; }
ppid_of()      { awk '/^PPid:/{print $2}' "/proc/$1/status" 2>/dev/null; }

# Walk ancestors for the Claude CLI process that owns this shell.
owner_pid=""
p="$$"
while [ -n "$p" ] && [ "$p" != "0" ] && [ "$p" != "1" ]; do
  if [ -f "$HOME/.claude/sessions/$p.json" ]; then owner_pid="$p"; break; fi
  p="$(ppid_of "$p")"
done
owner_start=""
[ -n "$owner_pid" ] && owner_start="$(starttime_of "$owner_pid")"

setsid "$@" >"$log" 2>&1 </dev/null &
pid=$!
starttime="$(starttime_of "$pid")"

if command -v jq >/dev/null 2>&1; then
  jq -n --argjson pid "$pid" --arg starttime "$starttime" \
        --arg owner_pid "$owner_pid" --arg owner_start "$owner_start" \
        --arg session "${CLAUDE_CODE_SESSION_ID:-unknown}" \
        --arg started "$(date -Is)" --args '
        {pid: $pid, starttime: $starttime, owner_pid: $owner_pid,
         owner_start: $owner_start, session: $session,
         started: $started, cmd: $ARGS.positional}' "$@" > "$reg/$pid.json"
else
  printf '{"pid":%d,"starttime":"%s","owner_pid":"%s","owner_start":"%s"}\n' \
    "$pid" "$starttime" "$owner_pid" "$owner_start" > "$reg/$pid.json"
fi

echo "managed pid $pid (owner CLI pid ${owner_pid:-unknown}; registry $reg/$pid.json)"

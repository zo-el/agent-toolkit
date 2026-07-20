#!/usr/bin/env bash
# Launcher for any long-lived background process an agent (or the session)
# starts — a dev server, watcher, tail. Registers the process so the reaper
# (reap-managed.sh) can find it once its owning session is gone; a raw
# `nohup … &` orphans to init and nobody ever cleans it up (verified).
#
#   spawn-managed.sh [--log FILE] -- cmd args…
#
# Prints the managed pid. The process runs in its own session/group (setsid),
# so the reaper can kill the whole tree at once. The registry entry records the
# kernel start time alongside the pid, so a recycled pid can never be mistaken
# for this process. Registry JSON is built with jq — a command containing
# quotes, backslashes, or newlines must not be able to corrupt an entry (a
# malformed entry would read back as an empty pid and be pruned, orphaning the
# process for good).
set -uo pipefail

reg="$HOME/.claude/managed-procs"
mkdir -p "$reg"

log=/dev/null
if [ "${1:-}" = "--log" ]; then log="$2"; shift 2; fi
[ "${1:-}" = "--" ] && shift
[ $# -gt 0 ] || { echo "usage: spawn-managed.sh [--log FILE] -- cmd args…" >&2; exit 2; }

setsid "$@" >"$log" 2>&1 </dev/null &
pid=$!

sid="${CLAUDE_CODE_SESSION_ID:-unknown}"
starttime="$(sed 's/.*) //' "/proc/$pid/stat" 2>/dev/null | awk '{print $20}')"

if command -v jq >/dev/null 2>&1; then
  jq -n --argjson pid "$pid" --arg session "$sid" --arg starttime "$starttime" \
        --arg started "$(date -Is)" --args '
        {pid: $pid, session: $session, starttime: $starttime,
         started: $started, cmd: $ARGS.positional}' "$@" > "$reg/$pid.json"
else
  # No jq: record the identifying fields only — never interpolate the command.
  printf '{"pid":%d,"session":"%s","starttime":"%s"}\n' \
    "$pid" "$sid" "$starttime" > "$reg/$pid.json"
fi

echo "managed pid $pid (owner session ${sid}; registry $reg/$pid.json)"

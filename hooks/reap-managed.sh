#!/usr/bin/env bash
# Reaper for spawn-managed.sh processes — the safety net under the agents'
# own cleanup discipline. Wired at SubagentStop / SessionEnd / SessionStart:
# a managed process whose OWNING SESSION is gone gets TERM, then KILL on a
# later pass once a grace period has elapsed. Processes of live sessions are
# never touched.
#
# Fail-safe in every direction it can't be sure:
#   - no jq                      → do nothing
#   - sessions registry absent   → do nothing (liveness is unknowable; killing
#                                  here would take out LIVE sessions' work)
#   - entry has no owner session → never killed, only pruned once dead
#   - pid recycled (start time no longer matches what was recorded) → prune the
#     stale entry, never signal, so an innocent new process is safe
# Liveness comes from ~/.claude/sessions/<pid>.json: a session file whose pid
# is running (and whose recorded procStart still matches) means that sessionId
# is live. Linux (/proc).
set -uo pipefail

reg="$HOME/.claude/managed-procs"
[ -d "$reg" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

GRACE=10   # seconds a TERMed process gets to exit before KILL

# Kernel start time (clock ticks since boot) for a pid — the field that makes a
# pid unambiguous across reuse. Strips through the last ')' first, because the
# comm field can itself contain spaces and parentheses.
starttime_of() {
  sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
}

# Live session ids — and whether the registry exists at all.
live=" "
seen_sessions=0
for f in "$HOME"/.claude/sessions/*.json; do
  [ -e "$f" ] || continue
  seen_sessions=$((seen_sessions + 1))
  spid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
  ssid="$(jq -r '.sessionId // empty' "$f" 2>/dev/null)"
  [ -n "$spid" ] && [ -n "$ssid" ] && kill -0 "$spid" 2>/dev/null && live="$live$ssid "
done
# No session files at all → we cannot tell live from dead. Do nothing.
[ "$seen_sessions" -gt 0 ] || exit 0

now="$(date +%s)"

for e in "$reg"/*.json; do
  [ -e "$e" ] || continue
  pid="$(jq -r '.pid // empty' "$e" 2>/dev/null)"
  sid="$(jq -r '.session // empty' "$e" 2>/dev/null)"
  st="$(jq -r '.starttime // empty' "$e" 2>/dev/null)"
  [ -n "$pid" ] || { rm -f "$e"; continue; }

  # Process already gone → drop the entry (and any term marker).
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$e" "$reg/$pid.term"
    continue
  fi

  # Pid reuse: the running process is not the one we registered → never signal.
  if [ -n "$st" ] && [ "$st" != "$(starttime_of "$pid")" ]; then
    rm -f "$e" "$reg/$pid.term"
    continue
  fi

  # Unknown owner → never kill proactively (fail-safe); live owner → spare.
  if [ -z "$sid" ] || [ "$sid" = "unknown" ]; then continue; fi
  case "$live" in *" $sid "*) continue ;; esac

  # Owner session is gone: TERM once, then KILL only after the grace period.
  if [ -f "$reg/$pid.term" ]; then
    termed="$(cat "$reg/$pid.term" 2>/dev/null || echo 0)"
    case "$termed" in ''|*[!0-9]*) termed=0 ;; esac
    if [ "$((now - termed))" -ge "$GRACE" ]; then
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
      rm -f "$e" "$reg/$pid.term"
    fi
  else
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    printf '%s\n' "$now" > "$reg/$pid.term"
  fi
done
exit 0

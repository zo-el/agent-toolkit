#!/usr/bin/env bash
# Reaper for spawn-managed.sh processes — the safety net under each agent's own
# cleanup discipline. Wired at SubagentStop / SessionEnd / SessionStart.
#
# What it guarantees: **nothing registered outlives the Claude session that
# started it.** A process whose owning CLI process is gone gets TERM, then KILL
# once a grace window has passed. It does NOT reap per-subagent — a subagent
# shares its parent's CLI process, so a server a subagent leaks lives until the
# session ends; stopping it before returning is the agent's own job (that is
# why every agent definition carries the discipline).
#
# Fail-safe in every direction it cannot be sure of — it would rather leak a
# process than kill live work:
#   - no jq                        → do nothing
#   - entry has no owner recorded  → never signalled, only pruned once dead
#   - our start time missing or changed (pid recycled) → prune, never signal
#   - owner alive, or owner's own start time changed   → spare
# Linux (/proc).
set -uo pipefail

reg="$HOME/.claude/managed-procs"
[ -d "$reg" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

GRACE=10   # seconds a TERMed process gets to exit before KILL

starttime_of() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'; }

now="$(date +%s)"

for e in "$reg"/*.json; do
  [ -e "$e" ] || continue
  pid="$(jq -r '.pid // empty' "$e" 2>/dev/null)"
  st="$(jq -r '.starttime // empty' "$e" 2>/dev/null)"
  opid="$(jq -r '.owner_pid // empty' "$e" 2>/dev/null)"
  ostart="$(jq -r '.owner_start // empty' "$e" 2>/dev/null)"
  [ -n "$pid" ] || { rm -f "$e"; continue; }

  # Process already gone → drop the entry (and any term marker).
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$e" "$reg/$pid.term"
    continue
  fi

  # Identity unverifiable or pid recycled → prune the stale entry, never signal.
  if [ -z "$st" ] || [ "$st" != "$(starttime_of "$pid")" ]; then
    rm -f "$e" "$reg/$pid.term"
    continue
  fi

  # No owner recorded → never kill proactively.
  [ -n "$opid" ] || continue

  # Owner still alive (same process, not a recycled pid) → in use, spare it.
  if kill -0 "$opid" 2>/dev/null; then
    [ -z "$ostart" ] || [ "$ostart" = "$(starttime_of "$opid")" ] && continue
  fi

  # Owning session is gone: TERM once, KILL only after the grace window.
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

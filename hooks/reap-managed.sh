#!/usr/bin/env bash
# Reaper for spawn-managed.sh processes — the safety net under each agent's own
# cleanup discipline. Wired at SessionEnd / SessionStart / SubagentStop.
#
# Two ways a managed process becomes reapable, because neither alone is enough:
#   1. Its owning CLI process is gone (crash, kill -9, machine restart). Only a
#      LATER session can observe this — at SessionEnd the CLI is still alive, by
#      construction, since the hook runs as its child.
#   2. The session that registered it is ending right now — SessionEnd passes
#      its own session_id on stdin, so the graceful path is handled at the
#      moment it happens rather than deferred to the next startup.
#
# Fail-safe wherever it cannot be sure — it would rather leak a process than
# kill live work:
#   - no jq                                   → do nothing
#   - our start time missing/changed (recycled pid) → prune, never signal
#   - no owner recorded and not the ending session  → never signalled
#   - owner alive, or its start time unreadable     → spare (only a definite
#     mismatch means the pid was recycled and the real owner is gone)
# Escalation is TERM, then KILL on a later pass once GRACE has elapsed.
# Linux (/proc).
set -uo pipefail

reg="$HOME/.claude/managed-procs"
input="$(cat 2>/dev/null || true)"
[ -d "$reg" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

GRACE=10   # seconds a TERMed process gets to exit before KILL

starttime_of() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'; }

# A session ending now takes its own managed processes with it.
ending=""
if [ -n "$input" ] \
   && [ "$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)" = "SessionEnd" ]; then
  ending="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
fi

now="$(date +%s)"

for e in "$reg"/*.json; do
  [ -e "$e" ] || continue
  pid="$(jq -r '.pid // empty' "$e" 2>/dev/null)"
  st="$(jq -r '.starttime // empty' "$e" 2>/dev/null)"
  opid="$(jq -r '.owner_pid // empty' "$e" 2>/dev/null)"
  ostart="$(jq -r '.owner_start // empty' "$e" 2>/dev/null)"
  sess="$(jq -r '.session // empty' "$e" 2>/dev/null)"
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

  reap=0
  if [ -n "$opid" ]; then
    if ! kill -0 "$opid" 2>/dev/null; then
      reap=1                                   # owning CLI is gone
    else
      ostart_now="$(starttime_of "$opid")"
      # Spare unless we can POSITIVELY show the pid was recycled: an unreadable
      # start time is uncertainty, and uncertainty must never kill.
      if [ -n "$ostart" ] && [ -n "$ostart_now" ] && [ "$ostart" != "$ostart_now" ]; then
        reap=1
      fi
    fi
  fi
  if [ -n "$ending" ] && [ -n "$sess" ] && [ "$sess" = "$ending" ]; then
    reap=1                                     # this session is ending now
  fi
  [ "$reap" -eq 1 ] || continue

  # TERM once, KILL only after the grace window has passed.
  #
  # The marker is named for a pid, so it must also carry the identity it was
  # written for. A marker left behind by an earlier holder of this pid reads as
  # "already TERMed, long ago" and would send this process straight to KILL with
  # no chance to shut down. Anything that doesn't match this exact process —
  # different start time, unreadable, or the older epoch-only format — counts as
  # not yet TERMed. The error is always toward giving grace, never skipping it.
  termed=0 m_at="" m_st=""
  if [ -f "$reg/$pid.term" ]; then
    read -r m_at m_st < "$reg/$pid.term" 2>/dev/null || true
    case "$m_at" in ''|*[!0-9]*) m_at=0 ;; esac
    [ "$m_st" = "$st" ] && termed="$m_at"
  fi

  if [ "$termed" -gt 0 ]; then
    if [ "$((now - termed))" -ge "$GRACE" ]; then
      kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
      rm -f "$e" "$reg/$pid.term"
    fi
  else
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
    printf '%s %s\n' "$now" "$st" > "$reg/$pid.term"
  fi
done

# Markers whose entry is gone can only mislead a future holder of that pid.
for m in "$reg"/*.term; do
  [ -e "$m" ] || continue
  b="${m##*/}"; b="${b%.term}"
  [ -e "$reg/$b.json" ] || rm -f "$m"
done
exit 0

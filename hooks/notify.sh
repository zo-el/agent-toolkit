#!/usr/bin/env bash
# Sound cue for the two events that mean "your turn":
#   alert  ← Notification : Claude needs you — a permission prompt or a question.
#   done   ← Stop         : the main agent finished its turn; the reply is ready.
# Wired to those events ONLY (never SubagentStop), so a background agent
# finishing stays silent — you hear it exactly when your eyes are needed.
#
# The kind is passed as $1 (no stdin parsing — the hook can't misread a payload).
# Cheap and fail-safe: pick the first available player + sound, play it detached,
# and always exit 0 — a notifier must never block a turn or error a session.
# Override a sound by dropping <toolkit>/sounds/<kind>.<ext> (oga/ogg/wav/mp3);
# otherwise a distinct freedesktop sound is used, and if none is found, silence.
#
# NOTIFY_DRYRUN=1 prints "player|sound" instead of playing — for tests/debugging.
set -uo pipefail

kind="${1:-done}"
root="$(cd "$(dirname "$0")/.." && pwd)"

case "$kind" in
  alert) fallbacks="window-attention message-new-instant dialog-warning bell" ;;
  done)  fallbacks="complete service-login dialog-information bell" ;;
  *)     exit 0 ;;                     # unknown kind → silence, never guess
esac

# Resolve the sound: a toolkit override wins, then a freedesktop fallback.
sound=""
for ext in oga ogg wav mp3; do
  if [ -f "$root/sounds/$kind.$ext" ]; then sound="$root/sounds/$kind.$ext"; break; fi
done
if [ -z "$sound" ]; then
  for name in $fallbacks; do
    cand="/usr/share/sounds/freedesktop/stereo/$name.oga"
    if [ -f "$cand" ]; then sound="$cand"; break; fi
  done
fi
[ -n "$sound" ] || exit 0            # nothing to play → silent, still success

# Resolve a player (first that exists). ffplay carries flags; keep them together.
player=""
for p in "paplay" "pw-play" "ffplay -nodisp -autoexit -loglevel quiet" "aplay -q"; do
  command -v "${p%% *}" >/dev/null 2>&1 && { player="$p"; break; }
done
[ -n "$player" ] || exit 0

if [ "${NOTIFY_DRYRUN:-}" = "1" ]; then
  printf '%s|%s\n' "${player%% *}" "$sound"
  exit 0
fi

# Detached + backgrounded so the hook returns instantly and the sound (≈1s)
# finishes on its own — short-lived, so nothing to register with the reaper.
setsid $player "$sound" >/dev/null 2>&1 &
exit 0

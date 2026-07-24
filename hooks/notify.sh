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
# NOTIFY_DRYRUN=1 prints "player|sound|xdg_runtime_dir" instead of playing — the
# resolved environment is reported too, so a test can catch a player that would
# fail to reach the audio server without making a sound.
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

# Resolve a player: the first that BOTH exists AND can decode the resolved sound.
# aplay speaks only WAV/AU/VOC/raw — never Ogg or mp3 — so it is skipped for any
# non-WAV sound. Choosing it for a .oga (every freedesktop fallback is Ogg) is a
# silent failure: aplay errors into the /dev/null redirect below and the turn
# goes unheard, while install.sh's doctor still sees a player on PATH and reports
# sound wired. ffplay carries flags; keep them together.
ext="${sound##*.}"
player=""
for p in "paplay" "pw-play" "ffplay -nodisp -autoexit -loglevel quiet" "aplay -q"; do
  cmd="${p%% *}"
  command -v "$cmd" >/dev/null 2>&1 || continue
  [ "$cmd" = "aplay" ] && [ "$ext" != "wav" ] && continue   # aplay can't decode Ogg/mp3
  player="$p"; break
done
[ -n "$player" ] || exit 0

# A hook is handed a bare environment, but EVERY player above reaches the audio
# server through $XDG_RUNTIME_DIR — paplay/pw-play via the PulseAudio/PipeWire
# socket, aplay/ffplay via ALSA's default PCM routing to that same socket. Absent
# it they all fail ("Connection refused"), and the redirect below hides it. Only
# default it; a session that provides one always wins. $EUID keeps this off PATH.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$EUID}"

if [ "${NOTIFY_DRYRUN:-}" = "1" ]; then
  printf '%s|%s|%s\n' "${player%% *}" "$sound" "$XDG_RUNTIME_DIR"
  exit 0
fi

# Detached + backgrounded so the hook returns instantly and the sound (≈1s)
# finishes on its own — short-lived, so nothing to register with the reaper.
setsid $player "$sound" >/dev/null 2>&1 &
exit 0

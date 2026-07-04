#!/usr/bin/env bash
# UserPromptSubmit hook — record the active cap from a typed /cap-* command (or
# "cap off") into a PER-SESSION state file, so concurrent sessions (even two on
# the same repo) never clobber each other's posture. The Linear guard and the
# statusline read the same per-session file.
#
# No jq/python dependency: session_id is pulled from the stdin JSON with grep,
# and the cap token is matched only at a COMMAND boundary — the start of the
# prompt value ("…":"/cap-…), the close of a <command-name> tag (>/cap-…), a
# line break, or string start — never mid-prose (space/letter-preceded) and
# never inside `inline code` (stripped first). So the soul files' own switching
# list and an incidental "/cap-developer" in a pasted doc cannot flip the
# posture. Falls back to the legacy global file if there is no session_id.
input="$(cat)"

sid="$(printf '%s' "$input" \
  | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
state="$HOME/.claude/.active-cap${sid:+-$sid}"

# Last qualifying token wins (a prompt rarely holds more than one).
cap="$(printf '%s' "$input" \
  | sed -E 's/`[^`]*`//g' \
  | grep -oiE '(^|[">]|\\n)/cap-(architect-designer|project-manager|developer)' \
  | grep -oiE 'cap-(architect-designer|project-manager|developer)' \
  | tail -n1 || true)"

if [ -n "$cap" ]; then
  printf '%s\n' "$cap" > "$state"
elif printf '%s' "$input" \
  | grep -qiE '"prompt"[[:space:]]*:[[:space:]]*"(\\n|\\t|[[:space:]])*cap[ -]off\b|cap[ -]off[[:space:].!]*(\\n)*"[[:space:]]*[,}]'; then
  # "cap off" counts only at the START or END of the typed prompt (leading
  # whitespace arrives JSON-escaped as \n/\t — matched literally). Every soul
  # file contains the phrase mid-text, so a pasted doc must never flip the
  # session bare.
  printf 'off\n' > "$state"
elif [ -f "$state" ]; then
  touch "$state"            # live session: refresh mtime so the prune below spares it
fi

# Reap per-session cap files from sessions gone silent >14 days (a killed session
# leaves an orphan; a live one refreshes its file above on every prompt).
find "$HOME/.claude" -maxdepth 1 -name '.active-cap-*' -mtime +14 -delete 2>/dev/null || true
exit 0

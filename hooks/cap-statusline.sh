#!/usr/bin/env bash
# statusLine command — show THIS SESSION's active cap as a colored chip (the
# visual cue when you switch caps). Reads the same per-session state file the
# guard uses (keyed by session_id from the status JSON on stdin), so the chip
# reflects this session, not whatever another session last selected. Outputs
# only the chip; enrich with model/dir/git via the statusline-setup skill.
input="$(cat)"
sid="$(printf '%s' "$input" \
  | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
state="$HOME/.claude/.active-cap${sid:+-$sid}"

case "$(cat "$state" 2>/dev/null)" in
  cap-architect-designer) printf '\033[34m🏛 Architect-Designer\033[0m' ;;  # blue
  cap-project-manager)    printf '\033[33m📋 Project-Manager\033[0m'    ;;  # amber
  cap-developer)          printf '\033[32m🔨 Developer\033[0m'          ;;  # green
  cap-reviewer)           printf '\033[31m🔍 Reviewer\033[0m'           ;;  # red
  off)                    printf '\033[2m○ cap off\033[0m'              ;;  # dim
  *)                      printf '\033[2m○ no cap\033[0m'               ;;  # dim
esac

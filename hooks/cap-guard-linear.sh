#!/usr/bin/env bash
# PreToolUse hook — Linear *writes* are Project-Manager-only; Linear *reads*
# are open to every posture. Wire it with matcher "mcp__linear-server__.*" so it
# only fires for Linear tools.
# Reads (list_/get_/search_/extract_) are informational → allowed for any cap
# (or none). Writes (save_/create_/delete_/prepare_, or anything new) mutate the
# board → PM-only, fail-closed: the write path is an allow-list of one cap, so a
# future/unrecognized Linear verb falls through to "treated as a write" and can
# never be silently writable from a non-PM posture. State is per-session (keyed
# by session_id from stdin), so another session's cap — even one on the same
# repo — never unblocks this one. Exit 2 stops the call and feeds the message
# back to Claude.
input="$(cat)"

tool="$(printf '%s' "$input" \
  | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"

# Reads are open to every posture — allow and stop here.
case "$tool" in
  mcp__linear-server__list_*|mcp__linear-server__get_*|mcp__linear-server__search_*|mcp__linear-server__extract_*)
    exit 0 ;;
esac

# Everything else mutates the board: PM-only, fail-closed.
sid="$(printf '%s' "$input" \
  | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
  | head -n1 | sed -E 's/.*"([^"]*)"$/\1/')"
state="$HOME/.claude/.active-cap${sid:+-$sid}"

active="$(cat "$state" 2>/dev/null || echo none)"
[ "$active" = "cap-project-manager" ] && exit 0

echo "⛔ Linear writes are Project-Manager-only (active cap: ${active}). Reads are open to every cap; to change the board, switch with /cap-project-manager." >&2
exit 2

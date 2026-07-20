#!/usr/bin/env bash
# PreToolUse[mcp__linear…] — the Linear board is shared, team-visible state, so
# every WRITE surfaces to the user before it lands. Reads are free.
#
# This is the mechanical half of linear-sync's "show the diff, then apply"
# discipline. It matters most inside the project-manager agent: a subagent's
# transcript is never seen, so without this a board mutation could happen with
# no user in the loop. Fail-closed by shape — anything that is not a known read
# verb is treated as a write.
#
# Only the project-manager agent carries Linear tools at all (its frontmatter
# allowlist); this gate covers the interactive session too, which has them by
# default.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || { echo "guard-linear: jq missing — guard inactive" >&2; exit 0; }
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
case "$tool" in mcp__linear*) ;; *) exit 0 ;; esac

# Read verbs are informational — allowed for anyone, no prompt.
case "$tool" in
  *__list_*|*__get_*|*__search_*|*__extract_*) exit 0 ;;
esac

jq -cn --arg t "$tool" '{hookSpecificOutput:{hookEventName:"PreToolUse",
  permissionDecision:"ask",
  permissionDecisionReason:("Linear board write (" + $t + ") — shared team state. Show the planned diff (linear-sync § Discipline) and confirm before it lands.")}}'
exit 0

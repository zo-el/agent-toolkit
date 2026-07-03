#!/usr/bin/env bash
# PostToolUse[Write|Edit] — re-sync the ~/.claude/skills symlinks, but only
# when the edited file actually lives under the toolkit's skills/ tree, so a
# mid-session skill add registers immediately without running the sync on
# every unrelated file edit (the old wiring ran it unconditionally).
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v jq >/dev/null 2>&1 || exit 0
fp="$(cat | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || exit 0
[ -n "$fp" ] || exit 0

case "$(realpath -m -- "$fp" 2>/dev/null || printf '%s' "$fp")" in
  "$root"/skills/*) exec "$root/install-skills.sh" >/dev/null 2>&1 ;;
esac
exit 0

#!/usr/bin/env bash
# PreToolUse[Write|Edit|NotebookEdit] — device config is not the workspace.
# core.md gates every edit outside the repo workspace on per-action approval;
# this makes that mechanical for the file tools (guard-git.sh covers the same
# ground for shell writes):
#
#   ask   ~/.claude/* (settings, CLAUDE.md, keybindings, commands, agents…),
#         ~/.gitconfig, anything under /etc, and the toolkit's own hooks/
#         (they ARE the enforcement layer — a silent edit could disable it).
#   allow ~/.claude/projects/** (Claude's own memory), ~/.claude/backups/**,
#         and paths that RESOLVE outside ~/.claude — e.g. a skill edited via
#         its ~/.claude/skills symlink lands in the toolkit repo: workspace.
#
# Paths are realpath-resolved first so a symlink can't dodge the gate in
# either direction. Fail-open without jq; sandbox + permission rules remain
# the hard layers.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || { echo "guard-config: jq missing — guard inactive" >&2; exit 0; }
fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)" || exit 0
[ -n "$fp" ] || exit 0

rp="$(realpath -m -- "$fp" 2>/dev/null || printf '%s' "$fp")"

ask() {
  jq -cn --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}

# The toolkit checkout is a repo workspace, but two kinds of write into it must
# be SEEN, not slipped into a session:
#   • hooks/ ARE the enforcement layer — always ask, even from inside the toolkit
#     (a silent hook edit could disable the guard). Unchanged.
#   • every other instruction-surface file (agents/*, core.md, skills/**,
#     install.sh) the future sessions load: free to edit FROM INSIDE the toolkit
#     (that is the current workspace — prompting there re-adds the friction the
#     working-directory approval removed), but a write reaching in from a session
#     whose cwd is OUTSIDE the checkout is the case that approval newly exposed —
#     ask there. cwd (a PreToolUse payload field) is realpath-resolved like the
#     target, so a symlink can't dodge the gate on either side.
toolkit="$(readlink -f "$HOME/.claude/agent-toolkit" 2>/dev/null || true)"
if [ -n "$toolkit" ]; then
  case "$rp" in
    "$toolkit"/hooks/*)
      ask "Guardrail edit: $fp changes the enforcement hooks themselves — review before it takes effect." ;;
    "$toolkit"/*)
      cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
      cwd_rp="$(realpath -m -- "$cwd" 2>/dev/null || printf '%s' "$cwd")"
      case "$cwd_rp" in
        "$toolkit"|"$toolkit"/*) exit 0 ;;   # toolkit edited from inside itself: free
        *) ask "Device-config gate (core.md): $fp is in the toolkit checkout but this session's cwd is outside it — review before it takes effect." ;;
      esac ;;
  esac
fi

case "$rp" in
  "$HOME"/.claude/projects/*|"$HOME"/.claude/backups/*) ;;   # memory + backups: Claude-owned
  "$HOME"/.claude/*) ask "Device-config gate (core.md): $fp is outside the repo workspace — needs per-action approval." ;;
  "$HOME"/.gitconfig|/etc/*) ask "Device-config gate (core.md): $fp is system/user config outside the workspace — needs per-action approval." ;;
esac

exit 0

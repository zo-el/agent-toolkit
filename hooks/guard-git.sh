#!/usr/bin/env bash
# PreToolUse[Bash] — mechanical enforcement of core.md's guardrails, so they
# hold in every permission mode instead of relying on the model remembering:
#
#   deny  public communication as the user (gh pr/issue comment, gh pr review,
#         mutating gh api calls on comment/review endpoints) — never allowed,
#         with or without approval; draft it and the user posts it themselves.
#   ask   publishing (push / PR / release / package publish) and state
#         mutation (commit, history rewrites, destructive rm outside the
#         workspace, shell writes into ~/.claude, global installs, sudo,
#         cron/service edits) — forces the show-the-plan-and-wait prompt.
#
# Matching is substring-regex over the whole command string, so compound
# commands ("cd x && git push") are caught. A quoted mention of a gated
# command (echo "git push") can trip an ask — fail-safe by design: worst case
# is one extra prompt. Fail-open without jq; the sandbox + permission rules
# stay as the hard layers below this one.
set -uo pipefail

input="$(cat)"
command -v jq >/dev/null 2>&1 || { echo "guard-git: jq missing — guard inactive" >&2; exit 0; }
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[ -n "$cmd" ] || exit 0

verdict() { # $1 = deny|ask, $2 = reason
  jq -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  exit 0
}

hit() { printf '%s' "$cmd" | grep -qE "$1"; }

# ── never: public words under the user's identity (core.md publishing rules) ──
hit '\bgh[[:space:]]+(pr|issue)[[:space:]]+comment\b' \
  && verdict deny "core.md: never post comments as the user — draft the text and let them post it."
hit '\bgh[[:space:]]+pr[[:space:]]+review\b' \
  && verdict deny "core.md: never submit PR reviews/replies as the user — address feedback through code; draft any needed reply for them."
hit '\bgh[[:space:]]+api\b' && hit '(comments|reviews|discussions)' \
  && hit '(--method[= ]+(POST|PUT|PATCH|DELETE)|[[:space:]]-(f|F)[[:space:]]|--(field|raw-field|input)\b)' \
  && verdict deny "core.md: mutating a comment/review/discussion endpoint posts as the user — never allowed."

# ── publish: nothing leaves the machine without the user seeing the plan ──
hit '\bgit[[:space:]]+push\b' \
  && verdict ask "Publish gate (core.md): git push needs a shown plan (commits + diff summary + exact target) and a fresh go-ahead."
hit '\bgh[[:space:]]+pr[[:space:]]+(create|edit|merge|close|reopen|ready|lock)\b' \
  && verdict ask "Publish gate (core.md): PR actions are outward-facing — show the plan and wait for explicit approval."
hit '\bgh[[:space:]]+(issue|release|gist)[[:space:]]+(create|edit|delete|close|reopen|upload)\b' \
  && verdict ask "Publish gate (core.md): outward-facing GitHub action — needs explicit per-action approval."
hit '\bgh[[:space:]]+repo[[:space:]]+(create|delete|edit|rename|archive|fork)\b' \
  && verdict ask "Publish gate (core.md): repository-level action — needs explicit per-action approval."
hit '\b(npm|yarn|pnpm|cargo)[[:space:]]+publish\b|\btwine[[:space:]]+upload\b' \
  && verdict ask "Publish gate (core.md): package publishing — needs explicit per-action approval."

# ── state mutation: per-action approval, a prior 'continue' never carries ──
hit '\bgit[[:space:]]+commit([[:space:]]|$|[;&|])' \
  && verdict ask "State-mutation gate (core.md): commits need per-action approval — message verbatim + diff summary."
hit '\bgit[[:space:]]+(rebase|cherry-pick|revert|filter-branch|filter-repo)\b' \
  && verdict ask "State-mutation gate (core.md): history operation — needs per-action approval; flag rewrites of pushed history."
hit '\bgit[[:space:]]+reset\b[^|;&]*--hard|\bgit[[:space:]]+clean\b[^|;&]*-[a-zA-Z]*f' \
  && verdict ask "State-mutation gate (core.md): discards working state — needs per-action approval."
hit '\bgit[[:space:]]+tag[[:space:]]+(-[dfasm]|[^-[:space:]])' \
  && verdict ask "State-mutation gate (core.md): tag operation — needs per-action approval."
hit '\bgit[[:space:]]+config\b[^|;&]*--global' \
  && verdict ask "State-mutation gate (core.md): ~/.gitconfig is outside the repo workspace — needs per-action approval."
hit '(^|[;&|][[:space:]]*)sudo\b' \
  && verdict ask "State-mutation gate (core.md): sudo touches the system outside the workspace — needs per-action approval."
hit '\b(apt|apt-get|dnf|pacman|brew)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*install\b|\bnpm[[:space:]]+(install|i)[[:space:]][^|;&]*(-g|--global)|\bcargo[[:space:]]+install\b|\bpip3?[[:space:]]+install[[:space:]][^|;&]*--user' \
  && verdict ask "State-mutation gate (core.md): global install — needs per-action approval."
hit '\bcrontab\b|\bsystemctl[[:space:]]+(--user[[:space:]]+)?(enable|disable|mask|unmask|edit)\b|\blaunchctl\b' \
  && verdict ask "State-mutation gate (core.md): launcher/cron/service entry — needs per-action approval."

# Recursive rm aimed outside the workspace (and outside /tmp) — the workspace
# itself is the agent's change set, so in-repo rm -r stays frictionless.
if hit '\brm\b[^|;&]*[[:space:]](-[a-zA-Z]*r|--recursive)'; then
  proj="${CLAUDE_PROJECT_DIR:-$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)}"
  # No known workspace → nothing can qualify as "inside it": fail closed.
  [ -n "$proj" ] || proj="/nonexistent-workspace"
  # Whole-token check (word-split, globbing off) so "./build" never reads as
  # the absolute "/build". Relative paths stay inside the workspace by nature;
  # ~, $HOME and absolute paths are judged against workspace + /tmp. Deleting
  # the workspace root itself still asks.
  set -f
  for tok in $cmd; do
    tok="${tok%[\"\']}"; tok="${tok#[\"\']}"
    case "$tok" in "~"*|"\$HOME/"*|/*) ;; *) continue ;; esac
    p="${tok/#\~/$HOME}"; p="${p/#\$HOME/$HOME}"
    case "$p" in
      "$proj"/*|/tmp/*|/dev/null) ;;
      *) verdict ask "State-mutation gate (core.md): recursive rm outside the workspace ($tok) — needs per-action approval." ;;
    esac
  done
  set +f
fi

# Shell writes into ~/.claude (device config) — memory (projects/), backups/,
# and the agent-toolkit symlink (a repo workspace in disguise) stay open.
if hit "(~|\\\$HOME|$HOME)/\\.claude/" && ! hit '\.claude/(projects|backups|agent-toolkit)/'; then
  hit '(>>?|\btee\b|\bsed\b[^|;&]*[[:space:]]-i|\bcp\b|\bmv\b|\bln\b|\brsync\b|\btruncate\b|\bchmod\b|\bchown\b)' \
    && verdict ask "State-mutation gate (core.md): shell write into ~/.claude device config — needs per-action approval."
fi

exit 0

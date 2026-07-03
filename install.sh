#!/usr/bin/env bash
# One-command install/repair for this toolkit on any machine:
#
#   ./install.sh            full install: symlink, skills, settings, pointer, doctor
#   ./install.sh --sync     SessionStart mode: symlink + skills + doctor, prints
#                           ONLY on problems (stdout lands in session context, so
#                           a broken install self-reports to the agent)
#   ./install.sh --dry-run  show every change a full install would make, write nothing
#
# Reliability model: device config (settings.json, ~/.claude/CLAUDE.md) points
# at the STABLE path ~/.claude/agent-toolkit — a symlink this script owns — so
# moving the repo never breaks the wiring again: re-run ./install.sh from the
# new location and only the symlink changes. Settings edits are jq merges that
# replace toolkit-managed entries (matched by "agent-toolkit|install-skills" in
# the command) and preserve everything else; originals are backed up to
# ~/.claude/backups first.
set -uo pipefail

# pwd -P: when invoked via the ~/.claude/agent-toolkit symlink (the
# SessionStart hook does), the physical path keeps ROOT at the real checkout —
# logical pwd would return the symlink itself and ln -sfn it into a self-loop.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDE_DIR="$HOME/.claude"
STABLE="$CLAUDE_DIR/agent-toolkit"
SETTINGS="$CLAUDE_DIR/settings.json"
POINTER="$CLAUDE_DIR/CLAUDE.md"
MODE="${1:-full}"
ts="$(date +%Y%m%d-%H%M%S)"
problems=0

say()  { [ "$MODE" != "--sync" ] && echo "$@" || true; }
warn() { echo "agent-toolkit doctor: ✗ $*"; problems=$((problems + 1)); }

need() { command -v "$1" >/dev/null 2>&1 || warn "missing dependency: $1"; }
need jq; need python3; need git

# ── 1. stable symlink ────────────────────────────────────────────────────────
if [ "$MODE" = "--dry-run" ]; then
  current="$(readlink "$STABLE" 2>/dev/null || echo "<none>")"
  [ "$current" = "$ROOT" ] || echo "symlink: $STABLE → $ROOT (was: $current)"
else
  mkdir -p "$CLAUDE_DIR"
  [ "$(readlink "$STABLE" 2>/dev/null)" = "$ROOT" ] || ln -sfn "$ROOT" "$STABLE"
fi

# ── 2. skills ────────────────────────────────────────────────────────────────
if [ "$MODE" = "--dry-run" ]; then
  echo "skills: $(find "$ROOT/skills" -name SKILL.md | wc -l | tr -d ' ') symlinked into $CLAUDE_DIR/skills"
else
  "$ROOT/install-skills.sh" >/dev/null 2>&1 || warn "install-skills.sh failed"
fi

# ── 3. settings.json: statusline + hooks on the stable path ─────────────────
desired_settings() {
  jq --arg base "$STABLE" '
    def ours: test("agent-toolkit|install-skills");
    def clean(a): (a // [])
      | map(select((((.hooks // []) | map(.command // "") | join(" ")) | ours) | not));
    .statusLine = {type: "command", command: ($base + "/hooks/statusline.py"), padding: 0}
    | .hooks.SessionStart = clean(.hooks.SessionStart) + [{
        matcher: "startup|resume|clear",
        hooks: [{type: "command", command: ($base + "/install.sh --sync")}]}]
    | .hooks.UserPromptSubmit = clean(.hooks.UserPromptSubmit) + [{
        hooks: [{type: "command", command: ($base + "/hooks/cap-set.sh")}]}]
    | .hooks.PreToolUse = clean(.hooks.PreToolUse) + [
        {matcher: "mcp__linear-server__.*",
         hooks: [{type: "command", command: ($base + "/hooks/cap-guard-linear.sh")}]},
        {matcher: "Bash",
         hooks: [{type: "command", command: ($base + "/hooks/guard-git.sh")}]},
        {matcher: "Write|Edit|NotebookEdit",
         hooks: [{type: "command", command: ($base + "/hooks/guard-config.sh")}]}]
    | .hooks.PostToolUse = clean(.hooks.PostToolUse) + [{
        matcher: "Write|Edit",
        hooks: [{type: "command", command: ($base + "/hooks/sync-on-skill-edit.sh")},
                {type: "command", command: ($base + "/hooks/format-on-edit.sh"), async: true}]}]
  ' "$1"
}

if [ ! -f "$SETTINGS" ]; then
  case "$MODE" in
    --dry-run) echo "settings: $SETTINGS would be created" ;;
    --sync)    warn "settings.json missing — run: $STABLE/install.sh" ;;
    *)         printf '{}\n' > "$SETTINGS" ;;
  esac
fi
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  new="$(desired_settings "$SETTINGS")"
  if [ -n "$new" ] && ! printf '%s\n' "$new" | cmp -s - "$SETTINGS"; then
    case "$MODE" in
      --dry-run)
        echo "settings: $SETTINGS would change:"
        printf '%s\n' "$new" | diff -u "$SETTINGS" - | sed 's/^/  /' | head -80
        ;;
      --sync)
        warn "settings.json is stale (old paths or missing hooks) — run: $STABLE/install.sh"
        ;;
      *)
        mkdir -p "$CLAUDE_DIR/backups"
        cp "$SETTINGS" "$CLAUDE_DIR/backups/settings.json.$ts"
        printf '%s\n' "$new" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
        say "✓ settings.json updated (backup: backups/settings.json.$ts)"
        ;;
    esac
  else
    say "✓ settings.json already current"
  fi
fi

# ── 4. device pointer ~/.claude/CLAUDE.md ────────────────────────────────────
pointer_content() {
  cat <<EOF
# Global instructions

All always-apply rules live in the portable agent-toolkit (its own git repo) — this file is only this device's pointer to it. New rules and learnings go INTO the toolkit, never here.

@$STABLE/CLAUDE.md
EOF
}

if ! pointer_content | cmp -s - "$POINTER" 2>/dev/null; then
  case "$MODE" in
    --dry-run)
      echo "pointer: $POINTER would change:"
      pointer_content | diff -u "$POINTER" - 2>/dev/null | sed 's/^/  /' | head -20
      ;;
    --sync)
      warn "~/.claude/CLAUDE.md does not point at $STABLE — run: $STABLE/install.sh"
      ;;
    *)
      mkdir -p "$CLAUDE_DIR/backups"
      [ -f "$POINTER" ] && cp "$POINTER" "$CLAUDE_DIR/backups/CLAUDE.md.$ts"
      pointer_content > "$POINTER"
      say "✓ ~/.claude/CLAUDE.md points at $STABLE"
      ;;
  esac
else
  say "✓ ~/.claude/CLAUDE.md already current"
fi

# ── 5. doctor: every wired path must exist and be executable ─────────────────
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r cmd; do
    exe="${cmd%% *}"
    case "$exe" in
      /*) [ -x "$exe" ] || warn "settings references missing/non-executable: $exe" ;;
    esac
  done < <(jq -r '([.statusLine.command] + [.hooks[]?[]?.hooks[]?.command]) | .[]? // empty' "$SETTINGS" 2>/dev/null)
fi
for f in "$ROOT"/hooks/*.sh "$ROOT"/hooks/*.py "$ROOT/install-skills.sh"; do
  [ -x "$f" ] || warn "not executable: $f"
done
if [ -f "$POINTER" ]; then
  while IFS= read -r imp; do
    [ -e "${imp#@}" ] || warn "~/.claude/CLAUDE.md imports a missing file: ${imp#@}"
  done < <(grep -oE '^@/[^ ]+' "$POINTER" || true)
fi
linked="$(find "$CLAUDE_DIR/skills" -maxdepth 1 -type l 2>/dev/null | wc -l | tr -d ' ')"
have="$(find "$ROOT/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
[ "$MODE" = "--dry-run" ] || [ "$linked" -ge "$have" ] || warn "only $linked of $have skills are linked — run: $STABLE/install-skills.sh"

if [ "$problems" -eq 0 ]; then
  say "✓ doctor: all checks green ($have skills, hooks wired via $STABLE)"
else
  say "doctor: $problems problem(s) above"
  exit 1
fi

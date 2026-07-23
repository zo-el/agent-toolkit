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
problems=0      # every doctor problem — drives the exit code
tk_problems=0   # toolkit-owned problems only — the version stamp is gated on
                # these, so a FOREIGN broken hook (a user command in settings.json
                # pointing at a missing path) can't suppress the freshness light.

say()  { [ "$MODE" != "--sync" ] && echo "$@" || true; }
# A toolkit-wiring problem: counts against both the exit code and the stamp gate.
warn() { echo "agent-toolkit doctor: ✗ $*"; problems=$((problems + 1)); tk_problems=$((tk_problems + 1)); }
# A problem in the user's own (non-toolkit) settings: still reported and still
# fails the doctor, but must not withhold the toolkit's own version stamp.
warn_foreign() { echo "agent-toolkit doctor: ✗ $*"; problems=$((problems + 1)); }

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

# ── 2.5 agents — COPIED, not symlinked (the agents file-watcher does not
# reliably follow symlinks); a manifest tracks toolkit-managed names so a
# renamed/removed agent is pruned without touching the user's own agents. ────
AGENTS_DST="$CLAUDE_DIR/agents"
MANIFEST="$AGENTS_DST/.toolkit-agents"
if [ "$MODE" = "--dry-run" ]; then
  echo "agents: $(ls "$ROOT"/agents/*.md 2>/dev/null | wc -l | tr -d ' ') copied into $AGENTS_DST"
else
  mkdir -p "$AGENTS_DST"
  if [ -f "$MANIFEST" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] && [ ! -f "$ROOT/agents/$name" ] && rm -f "$AGENTS_DST/$name"
    done < "$MANIFEST"
  fi
  : > "$MANIFEST.tmp"
  for a in "$ROOT"/agents/*.md; do
    [ -e "$a" ] || continue
    n="$(basename "$a")"
    if ! cmp -s "$a" "$AGENTS_DST/$n" 2>/dev/null; then
      # A destination we don't already manage is the user's own file — never
      # clobber it unseen; keep a dated copy before it's replaced.
      if [ -f "$AGENTS_DST/$n" ] && ! grep -qxF "$n" "$MANIFEST" 2>/dev/null; then
        mkdir -p "$CLAUDE_DIR/backups/agents"
        cp "$AGENTS_DST/$n" "$CLAUDE_DIR/backups/agents/$n.$ts"
        say "  ! kept your existing $n → backups/agents/$n.$ts"
      fi
      cp -f "$a" "$AGENTS_DST/$n"
    fi
    printf '%s\n' "$n" >> "$MANIFEST.tmp"
  done
  mv "$MANIFEST.tmp" "$MANIFEST"
  # One-time migration: entries written before ownership was re-keyed carry no
  # owner_pid, so the reaper can never judge them and would skip them forever.
  # Drop the records (never signal a process of unknown provenance) — anything
  # still running simply becomes unmanaged, which is where it started.
  legacy=0
  for m in "$CLAUDE_DIR"/managed-procs/*.json; do
    [ -e "$m" ] || continue
    if command -v jq >/dev/null 2>&1 && [ -z "$(jq -r '.owner_pid // empty' "$m" 2>/dev/null)" ]; then
      rm -f "$m"; legacy=$((legacy + 1))
    fi
  done
  [ "$legacy" -eq 0 ] || say "  ! dropped $legacy pre-upgrade managed-process record(s) — never signalled"
  # Reap any managed processes whose owning session is gone (cheap, idempotent).
  "$ROOT/hooks/reap-managed.sh" </dev/null 2>/dev/null || true
fi

# ── 3. settings.json: statusline + hooks on the stable path ─────────────────
desired_settings() {
  # NB: no apostrophes in this jq program — it is a single-quoted shell argument,
  # and bash -n does NOT catch a stray one: one trips it, but TWO balance out, so
  # the script parses and jq is silently handed a program TRUNCATED at the first
  # of them — at best empty output and a cheerful "already current", at worst a
  # settings.json written without every rule below that line — statusline and
  # every guard hook gone, silently. The guards are the apostrophe count (exactly
  # 2 — the delimiters below), the env-merge and full-wiring cases in tests/run.sh
  # (the latter asserts the TAIL of this program lands), and the doctor check in
  # section 5 that the wiring is present at all.
  jq --arg base "$STABLE" --arg cfg "$CLAUDE_DIR" --arg root "$ROOT" '
    def ours: test("agent-toolkit|install-skills");
    def clean(a): (a // [])
      | map(select((((.hooks // []) | map(.command // "") | join(" ")) | ours) | not));
    # In a permission rule path, a DOUBLED leading slash is what means absolute:
    # a single slash anchors the pattern at the settings directory instead of the
    # filesystem root, so dropping one slash makes the rule match nothing.
    def reads: (["plugins", "agents", "skills"] | map("Read(/" + $cfg + "/" + . + "/**)"))
      # projects/ is narrowed to the memory directories: agent memory is read all
      # the time, while the session transcripts sitting beside it can contain
      # anything ever pasted into a session. Rules match with gitignore semantics,
      # so a mid-pattern ** spans any number of directories.
      + ["Read(/" + $cfg + "/projects/**/memory/**)"]
      # Every ~/.claude/skills entry is a symlink into this checkout, and a read
      # is allowed only when the resolved realpath matches a rule too — so the
      # skill reads need the checkout itself, not just the symlink directory.
      + ["Read(/" + $root + "/**)"];
    # The del is cleanup, not config: CLAUDE_CODE_ENABLE_TASKS=0 is a real switch —
    # it turns the four Task tools off in favor of the older TodoWrite checklist.
    # Set here briefly and reverted: it could not help, because a server-side flag
    # keyed to the model was suppressing the Task tools and TodoWrite alike. A purely
    # additive merge would leave a stale =0 in every settings.json a previous install
    # wrote it into, genuinely disabling the Task tools once that flag lifts — so the
    # merge deletes the key instead of merely ceasing to write it.
    .env = ((.env // {}) + {CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"}
            | del(.CLAUDE_CODE_ENABLE_TASKS))
    # Auto mode: Claude judges each command itself instead of prompting for
    # everything — so background agents finish their work unattended, and no
    # hand-maintained list of build/test commands can go stale. It is safe here
    # only because the guard hooks below fire independently of permission mode
    # and re-introduce a prompt exactly where it matters (push, PR, comments as
    # the user, reset --hard, ~/.claude, Linear writes).
    | .permissions = ((.permissions // {}) + {defaultMode: "auto"})
    # Agents read plugin, agent and skill definitions and project memory under
    # ~/.claude constantly, and a read outside the workspace prompts even in auto
    # mode — stalling a background agent on a human who is not watching. Only the
    # paths above are pre-approved, and READ-only: settings.json (MCP plugins keep
    # API tokens in it), .credentials* and the session transcripts match none of
    # them, and a Read rule cannot loosen the config writes guard-config.sh gates.
    # Ours are dropped before being re-appended, so the merge stays idempotent.
    | .permissions.allow = (((.permissions.allow // []) - reads) + reads)
    # Enable pr-review-toolkit: the developer and reviewer self-review gate spawns
    # its agents (code-reviewer, silent-failure-hunter, etc.) on the local git diff.
    # The bundled /code-review is user-invocable only — a human pre-push gate, never
    # callable by a subagent — so enabling this is what gives the agents a review
    # gate at all. (Takes effect once the plugin is installed/cached; if it is not,
    # the user runs: /plugin install pr-review-toolkit@claude-plugins-official)
    | .enabledPlugins["pr-review-toolkit@claude-plugins-official"] = true
    # Superseded by hooks/notify.sh — disable the external notifications plugin
    # so a sound is not played twice (no-op if it was never installed).
    | (if (.enabledPlugins // {} | has("claude-notifications-go@claude-notifications-go"))
       then .enabledPlugins["claude-notifications-go@claude-notifications-go"] = false else . end)
    | .statusLine = {type: "command", command: ($base + "/hooks/statusline.py"), padding: 0}
    | .hooks.SessionStart = clean(.hooks.SessionStart) + [{
        matcher: "startup|resume|clear",
        hooks: [{type: "command", command: ($base + "/install.sh --sync")}]}]
    | .hooks.UserPromptSubmit = clean(.hooks.UserPromptSubmit)
    | .hooks.PreToolUse = clean(.hooks.PreToolUse) + [
        {matcher: "Bash",
         hooks: [{type: "command", command: ($base + "/hooks/guard-git.sh")}]},
        {matcher: "Write|Edit|NotebookEdit",
         hooks: [{type: "command", command: ($base + "/hooks/guard-config.sh")}]},
        {matcher: "mcp__linear.*",
         hooks: [{type: "command", command: ($base + "/hooks/guard-linear.sh")}]}]
    | .hooks.PostToolUse = clean(.hooks.PostToolUse) + [{
        matcher: "Write|Edit",
        hooks: [{type: "command", command: ($base + "/hooks/sync-on-skill-edit.sh")},
                {type: "command", command: ($base + "/hooks/format-on-edit.sh"), async: true}]}]
    | .hooks.SubagentStop = clean(.hooks.SubagentStop) + [{
        hooks: [{type: "command", command: ($base + "/hooks/reap-managed.sh")}]}]
    | .hooks.SessionEnd = clean(.hooks.SessionEnd) + [{
        hooks: [{type: "command", command: ($base + "/hooks/reap-managed.sh")}]}]
    # Sound only when it is your turn: a permission/question prompt (Notification)
    # and the main agent finishing (Stop). Not SubagentStop — background agents
    # stay silent. hooks/notify.sh takes the kind as an argument.
    | .hooks.Notification = clean(.hooks.Notification) + [{
        hooks: [{type: "command", command: ($base + "/hooks/notify.sh alert")}]}]
    | .hooks.Stop = clean(.hooks.Stop) + [{
        hooks: [{type: "command", command: ($base + "/hooks/notify.sh done")}]}]
    | .hooks |= with_entries(select((.value | length) > 0))
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
      /*) if [ ! -x "$exe" ]; then
            # A toolkit-wired command lives under $STABLE; anything else is one
            # of the user's own hooks — report it, but don't let it gate the stamp.
            case "$exe" in
              "$STABLE"/*) warn "settings references missing/non-executable: $exe" ;;
              *)           warn_foreign "settings references a missing/non-executable (non-toolkit) command: $exe" ;;
            esac
          fi ;;
    esac
  done < <(jq -r '([.statusLine.command] + [.hooks[]?[]?.hooks[]?.command]) | .[]? // empty' "$SETTINGS" 2>/dev/null)
fi
# …and our wiring must be PRESENT, not merely valid. The loop above only checks
# the paths it FINDS in settings, so a settings.json that lost the statusline and
# every hook — what a truncated merge program writes, see the NB in section 3 —
# sails through it with nothing left to check, and the next --sync compares that
# file against the same truncated output and calls it current. So the whole guard
# layer can go missing while both gates report green; this is the check that
# notices its own absence. Events are read from the merge program itself, so one
# wired tomorrow is covered the day it lands. Membership uses the same
# agent-toolkit marker the merge uses to recognize its own entries: whether those
# paths are current or exist at all is the staleness and path checks above. This
# asks only whether ours are PRESENT — never that nothing else is, so the hooks
# you wire yourself are none of its business.
# Skipped in --dry-run, where the file on disk is the BEFORE state this run fixes.
if [ "$MODE" != "--dry-run" ] && [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  wired="$(grep -oE '\.hooks\.[A-Za-z]+ = clean\([^)]*\) \+ \[' "$ROOT/install.sh" \
    | grep -oE '\.hooks\.[A-Za-z]+' | cut -d. -f3 | sort -u)"
  if ! gone="$(jq -r --arg want "$wired" '
    . as $s
    | ($want | split("\n") | map(select(length > 0))) as $want_ev
    | (($s.hooks // {}) | to_entries
       | map(select((.value | map((.hooks // []) | map(.command // ""))
                     | flatten | join(" ")) | test("agent-toolkit")))
       | map(.key)) as $have_ev
    | (if (($s.statusLine.command // "") | test("agent-toolkit")) then [] else ["statusLine"] end)
      + (($want_ev - $have_ev) | map("hooks." + .))
    | join(", ")' "$SETTINGS" 2>/dev/null)"; then
    warn "settings.json is unreadable, so the toolkit wiring cannot be verified — run: $STABLE/install.sh"
  elif [ -z "$wired" ]; then
    warn "no wired hook events found in the settings merge program — the wiring check cannot verify anything"
  elif [ -n "$gone" ]; then
    warn "settings.json is missing toolkit wiring ($gone) — run: $STABLE/install.sh"
  fi
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
# Count only the agents this toolkit owns — the user's own agents in the same
# directory must not make a missing toolkit agent look green.
agents_have=0; agents_copied=0
for a in "$ROOT"/agents/*.md; do
  [ -e "$a" ] || continue
  agents_have=$((agents_have + 1))
  cmp -s "$a" "$CLAUDE_DIR/agents/$(basename "$a")" 2>/dev/null && agents_copied=$((agents_copied + 1))
done
[ "$MODE" = "--dry-run" ] || [ "$agents_copied" -ge "$agents_have" ] || warn "only $agents_copied of $agents_have toolkit agents are installed/current — run: $STABLE/install.sh"
# Notification sounds are best-effort — a missing player degrades to silence,
# not a failed install; just tell the user so it isn't a silent surprise.
command -v paplay >/dev/null 2>&1 || command -v pw-play >/dev/null 2>&1 \
  || command -v ffplay >/dev/null 2>&1 || command -v aplay >/dev/null 2>&1 \
  || say "  ! no audio player (paplay/pw-play/ffplay/aplay) — notification sounds will be silent"

# Stamp the installed version — the statusline shows it (v<count>·<sha>) and
# flags ⚠ once the repo moves past it (a reinstall is pending). Full installs
# only (--sync/--dry-run don't re-apply agents/settings, so they don't stamp),
# and gated on toolkit-owned problems: once the toolkit's own wiring is applied,
# a FOREIGN broken hook must not withhold the "changes are applied" light.
if [ "$MODE" = "full" ] && [ "$tk_problems" -eq 0 ] && git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
  printf 'v%s·%s\n' \
    "$(git -C "$ROOT" rev-list --count HEAD)" \
    "$(git -C "$ROOT" rev-parse --short HEAD)" > "$CLAUDE_DIR/agent-toolkit-version"
fi

if [ "$problems" -eq 0 ]; then
  say "✓ doctor: all checks green ($have skills, hooks wired via $STABLE)"
else
  say "doctor: $problems problem(s) above"
  exit 1
fi

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
# Where every session is told to put its temporary files. Keyed to the uid, so
# this resolves per user rather than assuming the first-created 1000.
SCRATCH="/tmp/claude-$(id -u)"
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

# The stable symlink is this installer's own record of where the checkout lived
# last time. Read its target BEFORE section 1 re-aims it, so the settings merge
# can drop a moved-away checkout from additionalDirectories (see stale_checkouts).
PREV_ROOT="$(readlink "$STABLE" 2>/dev/null || true)"

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
# The hook wiring this toolkit owns, declared in ONE place: the merge below
# BUILDS settings.json from this list, and the doctor in section 5 checks the
# installed file AGAINST it — so what gets installed and what is required can
# never drift apart. The requirement used to be scraped out of this file's own
# source text (a grep for the merge's ".hooks.<Event> = clean(…) + [" lines),
# which meant reformatting one of those lines, or renaming clean, silently
# dropped that event from the REQUIREMENT: the doctor stayed green on a machine
# whose settings.json had lost the hook, so a PreToolUse entry could go missing
# and git push would run with no publish gate. A requirement that can shrink by
# itself is not a requirement.
# Commands are relative to $STABLE. matcher "" = the event takes no matcher.
# Notification (a permission/question prompt) and Stop (the main agent
# finishing) are the "it is your turn" sounds — notify.sh takes the kind as its
# argument. SubagentStop is deliberately NOT among them: a background agent
# finishing is not your cue to look, so it only runs the reaper.
TOOLKIT_WIRING='[
  {"event":"SessionStart","matcher":"startup|resume|clear",
   "hooks":[{"command":"/install.sh --sync"}]},
  {"event":"PreToolUse","matcher":"Bash",
   "hooks":[{"command":"/hooks/guard-git.sh"}]},
  {"event":"PreToolUse","matcher":"Write|Edit|NotebookEdit",
   "hooks":[{"command":"/hooks/guard-config.sh"}]},
  {"event":"PreToolUse","matcher":"mcp__linear.*",
   "hooks":[{"command":"/hooks/guard-linear.sh"}]},
  {"event":"PostToolUse","matcher":"Write|Edit",
   "hooks":[{"command":"/hooks/sync-on-skill-edit.sh"},
            {"command":"/hooks/format-on-edit.sh","async":true}]},
  {"event":"SubagentStop","matcher":"",
   "hooks":[{"command":"/hooks/reap-managed.sh"}]},
  {"event":"SessionEnd","matcher":"",
   "hooks":[{"command":"/hooks/reap-managed.sh"}]},
  {"event":"Notification","matcher":"",
   "hooks":[{"command":"/hooks/notify.sh alert"}]},
  {"event":"Stop","matcher":"",
   "hooks":[{"command":"/hooks/notify.sh done"}]}
]'

desired_settings() {
  # NB: no apostrophes in this jq program — it is a single-quoted shell argument,
  # and bash -n does NOT catch a stray one: one trips it, but TWO balance out, so
  # the script parses and jq is silently handed a program TRUNCATED at the first
  # of them — at best empty output and a cheerful "already current", at worst a
  # settings.json written without every rule below that line — statusline and
  # every guard hook gone, silently. The guards are the apostrophe count (exactly
  # 2 — the delimiters below; the TOOLKIT_WIRING declaration above holds none
  # either), the env-merge, working-directories and full-wiring cases in
  # tests/run.sh (the last of which asserts the TAIL of this program lands), and
  # the doctor check in section 5 that every declared hook is present.
  jq --arg base "$STABLE" --arg cfg "$CLAUDE_DIR" --arg root "$ROOT" --arg scratch "$SCRATCH" \
     --arg prevroot "$PREV_ROOT" --argjson wiring "$TOOLKIT_WIRING" '
    def ours: test("agent-toolkit|install-skills");
    def clean(a): (a // [])
      | map(select((((.hooks // []) | map(.command // "") | join(" ")) | ours) | not));
    # Retired: five Read() allow-rules earlier installs wrote, now subsumed by the
    # working directories below. They are subtracted rather than merely no longer
    # written, so a re-run cleans up after the runs that added them. In a
    # permission rule path a DOUBLED leading slash is what meant absolute, so they
    # are matched in exactly the form they were written.
    def retired_reads: (["plugins", "agents", "skills"] | map("Read(/" + $cfg + "/" + . + "/**)"))
      + ["Read(/" + $cfg + "/projects/**/memory/**)", "Read(/" + $root + "/**)"];
    # The directories agents work in outside the repo they were started in: the
    # config dir (plugin, agent and skill definitions, project memory), the
    # scratchpad root every session is told to use for temporary files, and this
    # checkout — every ~/.claude/skills entry is a symlink into it and access is
    # judged on the resolved realpath, so the symlink directory alone is not
    # enough. A path inside a working directory is approved BEFORE any allow-rule
    # is consulted, and for writes as much as reads — which is what stops a
    # background agent stalling on a prompt with no human watching. Wider than the
    # read-rules it replaces, by design: everything under ~/.claude is covered now,
    # settings.json and the session transcripts included. No guard is loosened —
    # PreToolUse hooks run ahead of permission rules either way, so guard-config
    # still asks on every ~/.claude write, guard-git on publishing and destructive
    # commands, guard-linear on board writes.
    def dirs: [$cfg, $scratch, $root];
    # A moved-and-reinstalled toolkit: the stable ~/.claude/agent-toolkit symlink
    # recorded the checkout path this installer last used, and $prevroot is that
    # target, read BEFORE section 1 re-aimed it. Subtracting it below drops the OLD
    # checkout dir instead of leaving it write-approved at a path that may later
    # hold an unrelated project — while a directory the user added by hand, never a
    # prior checkout, is untouched. Empty on a first install or when unmoved.
    def stale_checkouts: [$prevroot] | map(select(length > 0 and . != $root));
    # What the config working directory must NOT hand over: with ~/.claude
    # approved wholesale, a read of the credentials file is approved too — and so
    # is the settings file, which on another machine carries MCP tokens or API
    # keys in its env block, and this toolkit is built to travel. settings*.json,
    # not settings.json alone, so settings.local.json — same env shape, written by
    # update-config for machine-local secrets — is closed too, while unrelated JSON
    # (stats-cache.json and the like) stays readable. The backup entries cover the
    # historical copies written one directory over: backups/settings.json.<ts> this
    # installer writes on every settings change, and backups/.claude.json.backup.<ts>
    # Claude Code writes, which carries the mcpServers block and its tokens — each
    # scoped to its own filename, never to backups/ as a whole, which holds
    # unrelated files. A deny rule is evaluated BEFORE the working-directory check,
    # so these four close exactly those reads and nothing else.
    # Deliberately the Read TOOL only: the doctor in section 5 and the statusline
    # reach settings through jq and Python, which no permission rule governs, and
    # a shell read (cat, jq) stays open as well. The cost is the Edit tool, which
    # refuses a file it has not read: settings.json changes through this installer,
    # per the toolkit-maintenance skill, or through Bash — and the builtin
    # /statusline command, which reads it with the Read tool, will now refuse.
    # Leading slash DOUBLED for the same reason as the retired rules above: $cfg
    # is already absolute, and a single slash anchors the pattern at the settings
    # directory, where it would silently match nothing at all — a deny rule that
    # never fires reads exactly like a working one.
    def denied_reads: ["Read(/" + $cfg + "/.credentials.json)",
                       "Read(/" + $cfg + "/settings*.json)",
                       "Read(/" + $cfg + "/backups/settings.json.*)",
                       "Read(/" + $cfg + "/backups/.claude.json.backup.*)"];
    # AGENT_TEAMS turns on named teammates and SendMessage, the coordination layer
    # the orchestrator uses. MAX_SUBAGENT_SPAWN_DEPTH: as of Claude Code 2.1.217 a
    # subagent cannot spawn a subagent at all by default, which silently flattened
    # the two-level model every role definition is written around (a role fanning
    # out within its own role, a lead running its workers). The delegation cap is
    # two levels — main, then lead at 1, then developer at 2 — but the review gate
    # the developer must run spawns a pr-review-toolkit agent one deeper at 3
    # (exempt from the delegation cap, since a review is a gate not a hand-off), so
    # 3 is the depth that lets that gate run under a lead, and nothing beyond it.
    # The del is cleanup, not config: CLAUDE_CODE_ENABLE_TASKS=0 is a real switch —
    # it turns the four Task tools off in favor of the older TodoWrite checklist.
    # Set here briefly and reverted: it could not help, because a server-side flag
    # keyed to the model was suppressing the Task tools and TodoWrite alike. A purely
    # additive merge would leave a stale =0 in every settings.json a previous install
    # wrote it into, genuinely disabling the Task tools once that flag lifts — so the
    # merge deletes the key instead of merely ceasing to write it.
    .env = ((.env // {}) + {CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1",
                            CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH: "3"}
            | del(.CLAUDE_CODE_ENABLE_TASKS))
    # Auto mode: Claude judges each command itself instead of prompting for
    # everything — so background agents finish their work unattended, and no
    # hand-maintained list of build/test commands can go stale. It is safe here
    # only because the guard hooks below fire independently of permission mode
    # and re-introduce a prompt exactly where it matters (push, PR, comments as
    # the user, reset --hard, ~/.claude, Linear writes).
    | .permissions = ((.permissions // {}) + {defaultMode: "auto"})
    # Clean the retired rules out of whatever allowlist is there, leaving no empty
    # list behind if they were all of it.
    | .permissions.allow = ((.permissions.allow // []) - retired_reads)
    | .permissions |= (if (.allow | length) == 0 then del(.allow) else . end)
    # Ours are dropped before being re-appended, so the merge stays idempotent and
    # a directory added by hand is kept; stale_checkouts drops a moved-away prior
    # checkout in the same subtraction.
    | .permissions.additionalDirectories =
        (((.permissions.additionalDirectories // []) - (dirs + stale_checkouts)) + dirs)
    | .permissions.deny = (((.permissions.deny // []) - denied_reads) + denied_reads)
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
    # Hooks are BUILT from $wiring — the declaration above this function, which
    # is also what the doctor requires — rather than written out event by event
    # here, so the installed wiring and the required wiring are one text.
    # EVERY event is cleaned of toolkit entries first, not just the ones wired
    # today: an event we stop wiring (UserPromptSubmit, once) is then cleaned up
    # by the same pass instead of needing a line of its own to remember it.
    # Only arrays are cleaned — a malformed foreign entry is left exactly as it
    # is rather than failing the whole merge, which would write nothing at all
    # and report "already current".
    | .hooks = (reduce $wiring[] as $w (
        ((.hooks // {}) | with_entries(if (.value | type) == "array"
                                       then .value = clean(.value) else . end));
        .[$w.event] = ((.[$w.event] // []) + [
          (if $w.matcher == "" then {} else {matcher: $w.matcher} end)
          + {hooks: ($w.hooks | map({type: "command", command: ($base + .command)}
                                    + (if .async then {async: true} else {} end)))}]))
        | with_entries(select((.value | length) > 0)))
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
  new="$(desired_settings "$SETTINGS")"; ds_rc=$?
  # Tell a merge that ABORTED apart from "nothing to change". A pre-existing
  # permissions.allow that is a string (not an array), say, makes jq exit non-zero
  # with no output — and the old guard read that empty output as already-current:
  # green doctor, exit 0, a fresh version stamp, and NOTHING applied. So branch on
  # jq's status (and on empty output from a non-empty input, the truncated-program
  # case): fail loudly and, via warn, withhold the stamp rather than stamp a no-op.
  if [ "$ds_rc" -ne 0 ] || { [ -z "$new" ] && [ -s "$SETTINGS" ]; }; then
    warn "settings.json merge failed (jq error) — nothing applied, your settings.json is unchanged. Run: $STABLE/install.sh"
  elif ! printf '%s\n' "$new" | cmp -s - "$SETTINGS"; then
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
    # Strip a trailing arg ( --sync, alert, done) to the executable path without
    # letting a $HOME with a space break it. A toolkit command starts with $STABLE
    # and ends in .sh/.py; cut it at that suffix when an arg follows (safe with a
    # space in the path), else take the whole path. Only a foreign hook reaches the
    # last branch, where ${cmd%% *} strips its arg exactly as before — so no foreign
    # command regresses on account of this.
    case "$cmd" in
      "$STABLE"/*".sh "*) exe="${cmd%".sh "*}.sh" ;;
      "$STABLE"/*".py "*) exe="${cmd%".py "*}.py" ;;
      "$STABLE"/*)        exe="$cmd" ;;
      *)                  exe="${cmd%% *}" ;;
    esac
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
# notices its own absence. The requirement is TOOLKIT_WIRING, the same
# declaration the merge builds from, so one wired tomorrow is covered the day it
# lands and neither side can quietly stop matching the other. Every
# event/matcher/command triple must be there, not merely the event name: an
# event whose entry survives while guard-git.sh is dropped from it, or whose
# matcher no longer says Bash, leaves git push ungated exactly as a missing
# event would. Whether those paths exist and are current is the staleness and
# path checks above. This asks only whether ours are PRESENT — never that
# nothing else is, so the hooks you wire yourself are none of its business.
# Skipped in --dry-run, where the file on disk is the BEFORE state this run fixes.
if [ "$MODE" != "--dry-run" ] && [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  if ! gone="$(jq -r --argjson want "$TOOLKIT_WIRING" --arg base "$STABLE" '
    [ $want[] as $w | $w.hooks[] as $h
      | {event: $w.event, matcher: $w.matcher, command: ($base + $h.command)} ] as $want_t
    | [ (.hooks // {}) | to_entries[] as $ev | $ev.value[] as $e | ($e.hooks // [])[] as $h
        | {event: $ev.key, matcher: ($e.matcher // ""), command: ($h.command // "")} ] as $have_t
    | (if ((.statusLine.command // "") | test("agent-toolkit")) then [] else ["statusLine"] end)
      + (($want_t - $have_t) | map(.event + "[" + .matcher + "] " + .command))
    | join(", ")' "$SETTINGS" 2>/dev/null)"; then
    warn "the toolkit wiring cannot be verified (unreadable settings.json, or a TOOLKIT_WIRING declaration that is not valid JSON) — run: $STABLE/install.sh"
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
    # ^@/.+ (not [^ ]+): the import path is the whole rest of the line, so a $HOME
    # with a space must not be truncated at it — else the check tests the wrong path.
  done < <(grep -oE '^@/.+' "$POINTER" || true)
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
# pr-review-toolkit is ENABLED in settings above, but enabling is not installing
# (that needs `claude plugin install`, which this script deliberately does not
# run — the README documents it as a separate one-time step). The review gate
# every developer/reviewer agent spawns IS this plugin's agents, so without it
# that gate is an unknown-subagent-type error — no review at all. Read the
# authoritative install record and, if the plugin is absent, print the one-line
# fix. An advisory (! not ✗), unconditional so --sync surfaces it to the session:
# a reinstall of the toolkit cannot install the plugin, so this neither fails the
# doctor nor withholds the version stamp — it just tells you the step is pending.
if [ "$MODE" != "--dry-run" ] && command -v jq >/dev/null 2>&1; then
  plugin_key="pr-review-toolkit@claude-plugins-official"
  if ! jq -e --arg k "$plugin_key" '(.plugins[$k] // []) | length > 0' \
        "$CLAUDE_DIR/plugins/installed_plugins.json" >/dev/null 2>&1; then
    echo "agent-toolkit doctor: ! plugin $plugin_key is enabled but not installed — the review gate the agents spawn has nothing to run. Install once: claude plugin install $plugin_key --scope user (see README)"
  fi
fi
# Notification sounds are best-effort — a missing player degrades to silence,
# not a failed install; just tell the user so it isn't a silent surprise. This
# mirrors notify.sh's player resolution, not merely "is any player on PATH":
# paplay/pw-play/ffplay decode the .oga freedesktop fallbacks, but aplay speaks
# only WAV, so on an aplay-ONLY host the default .oga sounds play NOTHING — and
# the toolkit ships no .wav overrides by default. So aplay alone counts as wired
# only when sounds/alert.wav AND sounds/done.wav overrides exist (the coarse
# "will anything play?" call — notify.sh owns the exact per-sound format logic).
if command -v paplay >/dev/null 2>&1 || command -v pw-play >/dev/null 2>&1 \
   || command -v ffplay >/dev/null 2>&1; then
  :   # a richer player is present — it decodes the .oga freedesktop fallbacks
elif command -v aplay >/dev/null 2>&1; then
  if [ ! -f "$ROOT/sounds/alert.wav" ] || [ ! -f "$ROOT/sounds/done.wav" ]; then
    say "  ! only aplay is installed, which can't decode the default .oga notification sounds — notifications will be silent until a richer player (paplay/pw-play/ffplay) is installed or sounds/alert.wav + sounds/done.wav overrides are added"
  fi
else
  say "  ! no audio player (paplay/pw-play/ffplay/aplay) — notification sounds will be silent"
fi

# Stamp the installed version — the statusline shows it (v<count>·<sha>) and
# flags ⚠ once the repo moves past it (a reinstall is pending). Any run that
# actually applies pieces stamps: a full install, and --sync too — it re-links
# skills and re-copies agents (the ordinary edit-commit-new-session path, run by
# SessionStart), so the light must clear when it does, not wait for a manual full
# install. Only --dry-run writes nothing and is excluded. Gated on toolkit-owned
# problems: a stale settings.json raises one (under --sync it is reported, not
# applied) and holds the stamp back until a full install lands it, while a FOREIGN
# broken hook must not withhold the "changes are applied" light.
if [ "$MODE" != "--dry-run" ] && [ "$tk_problems" -eq 0 ] && git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
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

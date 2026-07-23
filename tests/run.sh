#!/usr/bin/env bash
# Regression suite for the toolkit's hooks. Run any time: ./tests/run.sh
# Each case pipes a synthetic hook payload and asserts the permission
# decision (allow = hook stayed silent). Exits nonzero on any failure so it
# can gate a commit.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0 fail=0

check() { # $1 hook script, $2 expected decision, $3 payload json, $4 label
  local out got
  out="$(printf '%s' "$3" | CLAUDE_PROJECT_DIR=/proj "$root/hooks/$1" 2>/dev/null)"
  if [ -z "$out" ]; then got="allow"; else
    got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo "unparseable")"
  fi
  if [ "$got" = "$2" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %-14s want=%-5s got=%-5s  %s\n' "$1" "$2" "$got" "$4"
  fi
}

bash_case() { # $1 expected, $2 command string
  check guard-git.sh "$1" \
    "$(jq -cn --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/proj"}')" \
    "$2"
}

file_case() { # $1 expected, $2 file_path
  check guard-config.sh "$1" \
    "$(jq -cn --arg f "$2" '{tool_name:"Write",tool_input:{file_path:$f}}')" \
    "$2"
}

# ── guard-git: deny — public words as the user, never allowed ──
bash_case deny 'gh pr comment 5 --body "looks good"'
bash_case deny 'gh issue comment 3 --body "fixed"'
bash_case deny 'gh pr review 5 --approve'
bash_case deny 'gh api repos/o/r/issues/3/comments -f body=hi'

# ── guard-git: ask — publishing ──
bash_case ask 'git push'
bash_case ask 'git push origin main --force'
bash_case ask 'cd /somewhere && git push'
bash_case ask 'gh pr create --fill'
bash_case ask 'gh pr merge 5 --squash'
bash_case ask 'gh release create v1.0'
bash_case ask 'npm publish'
bash_case ask 'cargo publish'
bash_case ask 'twine upload dist/*'

# ── guard-git: ask — destructive or device state ──
bash_case ask 'git reset --hard HEAD~1'
bash_case ask 'git clean -fd'
bash_case ask 'git filter-branch --force --all'
bash_case ask 'git config --global user.email x@y.z'
bash_case ask 'sudo apt install foo'
bash_case ask 'apt install foo'
bash_case ask 'npm install -g something'
bash_case ask 'cargo install something'
bash_case ask 'pip install --user something'
bash_case ask 'crontab -e'
bash_case ask 'systemctl enable myservice'
bash_case ask 'rm -rf /home/nobody/stuff'
bash_case ask 'rm -rf ~/stuff'
bash_case ask 'rm --recursive --force /opt/thing'
bash_case ask 'echo x > ~/.claude/settings.json'
bash_case ask 'mv /tmp/s.json $HOME/.claude/settings.json'
bash_case ask 'sed -i "s/a/b/" ~/.claude/CLAUDE.md'

# ── guard-git: allow — everyday work incl. local git workflow ──
bash_case allow 'git status'
bash_case allow 'git log --oneline -5'
bash_case allow 'git commit -m "feat: x"'
bash_case allow 'git commit --amend --no-edit'
bash_case allow 'git checkout -b feature/thing'
bash_case allow 'git branch experiment'
bash_case allow 'git rebase -i HEAD~3'
bash_case allow 'git cherry-pick abc123'
bash_case allow 'git merge feature/thing'
bash_case allow 'git tag v1.0'
bash_case allow 'git tag -d v1.0'
bash_case allow 'git tag'
bash_case allow 'git tag -l "v*"'
bash_case allow 'git tag --list'
bash_case allow 'git config user.name'
bash_case allow 'ls -la && cargo test'
bash_case allow 'rm -rf ./build'
bash_case allow 'rm -rf /proj/target'
bash_case allow 'rm -rf /tmp/scratch'
bash_case allow 'npm install left-pad'
bash_case allow 'pip install -e .'
bash_case allow 'gh pr view 5'
bash_case allow 'gh pr list'
bash_case allow 'gh api repos/o/r/issues/3/comments'
bash_case allow 'cat ~/.claude/settings.json'
bash_case allow 'jq .effortLevel ~/.claude/settings.json'
bash_case allow 'cp report.md ~/.claude/backups/report.md'
bash_case allow 'echo note > ~/.claude/projects/p/memory/note.md'
bash_case allow 'systemctl status myservice'
bash_case allow 'git commit-graph write'

# ── guard-config: device config asks, Claude-owned dirs and repos don't ──
file_case ask "$HOME/.claude/settings.json"
file_case ask "$HOME/.claude/settings.local.json"
file_case ask "$HOME/.claude/CLAUDE.md"
file_case ask "$HOME/.claude/keybindings.json"
file_case ask "$HOME/.claude/commands/new.md"
file_case ask "$HOME/.gitconfig"
file_case ask "/etc/hosts"
file_case allow "$HOME/.claude/projects/-some-project/memory/fact.md"
file_case allow "$HOME/.claude/backups/settings.json.bak"
file_case allow "/proj/src/main.rs"
file_case allow "/tmp/scratch/notes.md"

# ── statusline: never crashes, always prints a line ──
sl() {
  local out
  out="$(printf '%s' "$1" | python3 "$root/hooks/statusline.py" 2>/dev/null)"
  if [ -n "$out" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL statusline.py  empty/crash on: %s\n' "$2"
  fi
}
sl '{}' 'empty object'
sl '' 'empty stdin'
sl '{"model":{"id":"claude-fable-5[1m]","display_name":"Fable 5"},"effort":{"level":"max"},"context_window":{"used_percentage":42,"context_window_size":1000000,"total_input_tokens":420000},"cost":{"total_cost_usd":1.5},"rate_limits":{"five_hour":{"used_percentage":23.5},"seven_day":{"used_percentage":81.2}},"workspace":{"current_dir":"/tmp"}}' 'full native payload'
sl '{"transcript_path":"/nonexistent.jsonl","workspace":{"current_dir":"/nonexistent-dir"}}' 'bogus paths'

# ── guard-linear: reads free, writes ask ──
linear_case() { # $1 expected, $2 tool name
  check guard-linear.sh "$1" "$(jq -cn --arg t "$2" '{tool_name:$t,tool_input:{}}')" "$2"
}
linear_case allow mcp__linear__list_issues
linear_case allow mcp__linear__get_issue
linear_case allow mcp__linear__search_documentation
linear_case ask   mcp__linear__save_issue
linear_case ask   mcp__linear__save_milestone
linear_case ask   mcp__linear__create_issue_label
linear_case ask   mcp__linear__delete_comment
linear_case ask   mcp__linear__some_future_verb
check guard-linear.sh allow '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 'non-linear tool untouched'

# ── spawn-managed + reap-managed: ownership is the owning CLI process ──
# Entries are hand-built so each rule is proven in isolation; ownership is a
# (pid, kernel start time) pair, never a session id.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/managed-procs"
st_of() { sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'; }
spawn_sleep() { setsid sleep 300 >/dev/null 2>&1 & echo $!; }
entry() { # $1 pid, $2 owner_pid, $3 owner_start, $4 starttime-override("" = real)
  local s="${4:-$(st_of "$1")}"
  jq -n --argjson pid "$1" --arg st "$s" --arg op "$2" --arg os "$3" \
    '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os}' \
    > "$fh/.claude/managed-procs/$1.json"
}
reap() { HOME="$fh" "$root/hooks/reap-managed.sh"; }
alive() { kill -0 "$1" 2>/dev/null; }

dead_owner="$(sh -c 'echo $$')"          # exited immediately → a dead pid
p_dead="$(spawn_sleep)";    entry "$p_dead"    "$dead_owner" ""
p_live="$(spawn_sleep)";    entry "$p_live"    "$$"          "$(st_of $$)"
p_noowner="$(spawn_sleep)"; entry "$p_noowner" ""            ""
p_recycled="$(spawn_sleep)"; entry "$p_recycled" "$dead_owner" "" "1"   # start time mismatch
entry 99999999 "$dead_owner" ""                                        # pid long gone

reap; reap
for i in 1 2 3 4 5; do alive "$p_dead" || break; sleep 0.2; done

if ! alive "$p_dead" && [ ! -e "$fh/.claude/managed-procs/$p_dead.json" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   dead-owner process not reaped"
fi
if alive "$p_live"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   live-owner process was killed"
fi
if alive "$p_noowner"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   unowned process was killed (must be fail-safe)"
fi
if alive "$p_recycled" && [ ! -e "$fh/.claude/managed-procs/$p_recycled.json" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   recycled pid must be pruned WITHOUT signalling"
fi
if [ ! -e "$fh/.claude/managed-procs/99999999.json" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   dead-pid entry not pruned"
fi
kill "$p_live" "$p_noowner" "$p_recycled" 2>/dev/null; rm -rf "$fh"

# ── a session id that rotates (/clear, /resume) must NOT cost a live process ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/managed-procs"
p_rotate="$(setsid sleep 300 >/dev/null 2>&1 & echo $!)"
jq -n --argjson pid "$p_rotate" --arg st "$(sed 's/.*) //' /proc/$p_rotate/stat | awk '{print $20}')" \
  --arg op "$$" --arg os "$(sed 's/.*) //' /proc/$$/stat | awk '{print $20}')" \
  --arg session "an-old-rotated-away-session-id" \
  '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os, session:$session}' \
  > "$fh/.claude/managed-procs/$p_rotate.json"
HOME="$fh" "$root/hooks/reap-managed.sh"; HOME="$fh" "$root/hooks/reap-managed.sh"
if kill -0 "$p_rotate" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   killed a live owner's process after its session id rotated"
fi
kill "$p_rotate" 2>/dev/null; rm -rf "$fh"

# ── TERM is not escalated to KILL inside the grace window ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/managed-procs"
p_grace="$(setsid sh -c 'trap "" TERM; sleep 300' >/dev/null 2>&1 & echo $!)"
dead_owner2="$(sh -c 'echo $$')"
jq -n --argjson pid "$p_grace" --arg st "$(sed 's/.*) //' /proc/$p_grace/stat | awk '{print $20}')" \
  --arg op "$dead_owner2" --arg os "" \
  '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os}' \
  > "$fh/.claude/managed-procs/$p_grace.json"
HOME="$fh" "$root/hooks/reap-managed.sh"; sleep 0.3; HOME="$fh" "$root/hooks/reap-managed.sh"
if kill -0 "$p_grace" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   SIGKILLed inside the grace window (no time to shut down)"
fi
kill -KILL -- "-$p_grace" 2>/dev/null; rm -rf "$fh"

# ── a stale .term marker must not skip TERM and SIGKILL a fresh process ──
# Markers are named for a pid, so one left by an earlier holder of that pid used
# to read as "TERMed long ago" → straight to KILL, no grace. The process here
# ignores TERM, so surviving a pass proves it was TERMed and not KILLed.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/managed-procs"
p_stale="$(setsid sh -c 'trap "" TERM; sleep 300' >/dev/null 2>&1 & echo $!)"
dead_owner3="$(sh -c 'echo $$')"
jq -n --argjson pid "$p_stale" --arg st "$(sed 's/.*) //' /proc/$p_stale/stat | awk '{print $20}')" \
  --arg op "$dead_owner3" --arg os "" \
  '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os}' \
  > "$fh/.claude/managed-procs/$p_stale.json"
echo "$(( $(date +%s) - 9999 ))" > "$fh/.claude/managed-procs/$p_stale.term"
HOME="$fh" "$root/hooks/reap-managed.sh" </dev/null; sleep 0.3
if kill -0 "$p_stale" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   stale .term marker skipped TERM and SIGKILLed outright"
fi
kill -KILL -- "-$p_stale" 2>/dev/null

# ── a marker with no surviving entry is swept, so no future pid inherits it ──
echo "123 456" > "$fh/.claude/managed-procs/424242.term"
rm -f "$fh/.claude/managed-procs"/*.json
HOME="$fh" "$root/hooks/reap-managed.sh" </dev/null
if [ ! -e "$fh/.claude/managed-procs/424242.term" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   orphan .term marker not swept"
fi
rm -rf "$fh"

# ── the kill-vs-spare branch: uncertainty spares, only a positive mismatch reaps ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/managed-procs"
# (a) live owner, start time NOT recorded → unverifiable → must be SPARED
p_unverif="$(setsid sleep 300 >/dev/null 2>&1 & echo $!)"
jq -n --argjson pid "$p_unverif" --arg st "$(sed 's/.*) //' /proc/$p_unverif/stat | awk '{print $20}')" \
  --arg op "$$" --arg os "" \
  '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os}' \
  > "$fh/.claude/managed-procs/$p_unverif.json"
# (b) live owner pid, but a DIFFERENT process than recorded → pid recycled → reap
p_recyc_owner="$(setsid sleep 300 >/dev/null 2>&1 & echo $!)"
jq -n --argjson pid "$p_recyc_owner" --arg st "$(sed 's/.*) //' /proc/$p_recyc_owner/stat | awk '{print $20}')" \
  --arg op "$$" --arg os "999999999" \
  '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os}' \
  > "$fh/.claude/managed-procs/$p_recyc_owner.json"
HOME="$fh" "$root/hooks/reap-managed.sh" </dev/null
for i in 1 2 3 4 5; do kill -0 "$p_recyc_owner" 2>/dev/null || break; sleep 0.2; done
if kill -0 "$p_unverif" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   killed a LIVE owner's process when its start time was unverifiable"
fi
if ! kill -0 "$p_recyc_owner" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   owner pid recycled (start time mismatch) — process should be reaped"
fi
kill "$p_unverif" "$p_recyc_owner" 2>/dev/null; rm -rf "$fh"

# ── SessionEnd reaps the ending session's own processes (owner still alive) ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/managed-procs"
p_ending="$(setsid sleep 300 >/dev/null 2>&1 & echo $!)"
jq -n --argjson pid "$p_ending" --arg st "$(sed 's/.*) //' /proc/$p_ending/stat | awk '{print $20}')" \
  --arg op "$$" --arg os "$(sed 's/.*) //' /proc/$$/stat | awk '{print $20}')" --arg sess "ending-sess" \
  '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os, session:$sess}' \
  > "$fh/.claude/managed-procs/$p_ending.json"
printf '{"hook_event_name":"SessionEnd","session_id":"ending-sess"}' \
  | HOME="$fh" "$root/hooks/reap-managed.sh"
for i in 1 2 3 4 5; do kill -0 "$p_ending" 2>/dev/null || break; sleep 0.2; done
if ! kill -0 "$p_ending" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   SessionEnd did not reap the ending session's process"
fi
# …and a DIFFERENT session ending must not touch it
p_other="$(setsid sleep 300 >/dev/null 2>&1 & echo $!)"
jq -n --argjson pid "$p_other" --arg st "$(sed 's/.*) //' /proc/$p_other/stat | awk '{print $20}')" \
  --arg op "$$" --arg os "$(sed 's/.*) //' /proc/$$/stat | awk '{print $20}')" --arg sess "mine" \
  '{pid:$pid, starttime:$st, owner_pid:$op, owner_start:$os, session:$sess}' \
  > "$fh/.claude/managed-procs/$p_other.json"
printf '{"hook_event_name":"SessionEnd","session_id":"someone-elses"}' \
  | HOME="$fh" "$root/hooks/reap-managed.sh"
if kill -0 "$p_other" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   another session ending killed our process"
fi
kill "$p_other" 2>/dev/null; rm -rf "$fh"

# ── end-to-end: a REAL spawn-managed entry survives a reap pass (schema contract) ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/sessions"
printf '{"pid":%d,"sessionId":"s"}' "$$" > "$fh/.claude/sessions/$$.json"
p_e2e="$(HOME="$fh" CLAUDE_CODE_SESSION_ID=s "$root/hooks/spawn-managed.sh" -- sleep 300 \
  | sed -n 's/^managed pid \([0-9]*\).*/\1/p')"
HOME="$fh" "$root/hooks/reap-managed.sh" </dev/null
if kill -0 "$p_e2e" 2>/dev/null && [ -e "$fh/.claude/managed-procs/$p_e2e.json" ]; then
  pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   writer/reader schema mismatch — real entry mis-handled"
fi
# and SessionEnd for that same session does reap it
printf '{"hook_event_name":"SessionEnd","session_id":"s"}' | HOME="$fh" "$root/hooks/reap-managed.sh"
for i in 1 2 3 4 5; do kill -0 "$p_e2e" 2>/dev/null || break; sleep 0.2; done
if ! kill -0 "$p_e2e" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   real spawn-managed entry not reaped at its SessionEnd"
fi
kill "$p_e2e" 2>/dev/null; rm -rf "$fh"

# ── spawn-managed: tricky command stays valid JSON; owner recorded from ancestry ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/sessions"
printf '{"pid":%d,"sessionId":"s"}' "$$" > "$fh/.claude/sessions/$$.json"
p_json="$(HOME="$fh" "$root/hooks/spawn-managed.sh" -- sh -c 'sleep 300 # a "quoted" \back\slash
newline' | sed -n 's/^managed pid \([0-9]*\).*/\1/p')"
if jq -e '.pid' "$fh/.claude/managed-procs/$p_json.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL spawn-managed  registry entry is not valid JSON for a tricky command"
fi
if [ "$(jq -r '.owner_pid' "$fh/.claude/managed-procs/$p_json.json" 2>/dev/null)" = "$$" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL spawn-managed  owner CLI pid not discovered from process ancestry"
fi
kill -KILL -- "-$p_json" 2>/dev/null; kill "$p_json" 2>/dev/null; rm -rf "$fh"

# ── install.sh invoked via its own stable symlink must not self-loop ──
fh="$(mktemp -d)"
if HOME="$fh" "$root/install.sh" >/dev/null 2>&1 \
   && HOME="$fh" "$fh/.claude/agent-toolkit/install.sh" --sync >/dev/null 2>&1 \
   && [ "$(readlink -f "$fh/.claude/agent-toolkit")" = "$root" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL install.sh     symlink self-loops when run via ~/.claude/agent-toolkit"
fi
rm -rf "$fh"

# ── install.sh: a FOREIGN broken hook fails the doctor (exit 1) but must NOT ──
# ── suppress the version stamp — only toolkit-owned problems gate the stamp   ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/nonexistent/foreign-hook.sh"}]}]}}\n' \
  > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && [ -s "$fh/.claude/agent-toolkit-version" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     foreign broken hook must fail the doctor yet still stamp the version (rc=$rc)"
fi
rm -rf "$fh"

# ── install.sh: desired_settings actually enables the pr-review-toolkit plugin ──
# The jq program is one single-quoted shell arg — an apostrophe inside it silently
# breaks the program → empty output → install falls through to "already current"
# and the enabledPlugins entry never lands. Seed a sibling plugin and prove the
# merge ADDS the entry while keeping the sibling: one assertion catches both the
# silent no-op and a clobbering merge.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
printf '{"enabledPlugins":{"other-plugin@vendor":true}}\n' > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
if jq -e '.enabledPlugins["pr-review-toolkit@claude-plugins-official"] == true
          and .enabledPlugins["other-plugin@vendor"] == true' \
     "$fh/.claude/settings.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     pr-review-toolkit plugin not enabled (or merge clobbered a sibling)"
fi
rm -rf "$fh"

# ── install.sh: the .env merge writes the toolkit env var, keeping yours ──────
# AGENT_TEAMS=1 is the only env var the toolkit sets. CLAUDE_CODE_ENABLE_TASKS=0
# was set here briefly and reverted (the task list is gated server-side, so it
# never brought TodoWrite back), so the merge must also DELETE it from a
# settings.json a previous install wrote it into — an additive merge would strand
# the dead key. Same silent single-quoted-jq trap as above, so seed both the
# retired key and an unrelated one: one assertion then covers the var going
# missing, the dead flag surviving, and your own key being clobbered.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
printf '{"env":{"MY_OWN_VAR":"keep","CLAUDE_CODE_ENABLE_TASKS":"0"}}\n' > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
if jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1"
          and (.env | has("CLAUDE_CODE_ENABLE_TASKS") | not)
          and .env.MY_OWN_VAR == "keep"' \
     "$fh/.claude/settings.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     env merge wrong: AGENT_TEAMS missing (the single-quoted-jq trap), the retired ENABLE_TASKS not cleaned out, or your own .env key clobbered"
fi
rm -rf "$fh"

# ── install.sh: reads of the non-secret ~/.claude dirs are pre-approved ──────
# Reads outside the workspace prompt even in auto mode, which stalls a background
# agent on a human. Seed a settings.json that already carries every permissions
# field, so one assertion covers every failure mode: the entries missing (the
# same single-quoted-jq trap as above), the merge dropping fields the user set,
# a secret-bearing path (settings.json / credentials / a blanket ~/.claude/**)
# creeping into the allowlist, the blanket projects rule returning (only the
# memory dirs are readable — the session transcripts beside them stay gated),
# and the checkout rule going missing (every ~/.claude/skills entry is a symlink
# into the checkout, and a read is allowed only when the resolved realpath
# matches a rule too). Paths follow HOME, and the DOUBLED leading slash is the
# part that means absolute — a single slash would anchor the pattern at the
# settings directory and match nothing. Installing twice must change nothing:
# our rules are dropped before being re-appended.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"],"deny":["Read(//etc/shadow)"],"ask":["Bash(curl:*)"],"additionalDirectories":["/srv/shared"],"defaultMode":"plan"}}' \
  > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
cp "$fh/.claude/settings.json" "$fh/pass1.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
if cmp -s "$fh/pass1.json" "$fh/.claude/settings.json" \
   && jq -e --arg cfg "$fh/.claude" --arg co "$(cd "$root" && pwd -P)" '
      ((["plugins","agents","skills"] | map("Read(/" + $cfg + "/" + . + "/**)"))
       + ["Read(/" + $cfg + "/projects/**/memory/**)", "Read(/" + $co + "/**)"]) as $want
      | (.permissions.allow // []) as $got
      | ($want - $got) == []
        and ($got | index("Read(/" + $cfg + "/projects/**)")) == null
        and ($got | length) == ($got | unique | length)
        and ($got | index("Bash(ls:*)")) != null
        and .permissions.deny == ["Read(//etc/shadow)"]
        and .permissions.ask == ["Bash(curl:*)"]
        and .permissions.additionalDirectories == ["/srv/shared"]
        and .permissions.defaultMode == "auto"
        and ($got | map(select(test("credentials|settings\\.json|\\.claude/\\*\\*"))) | length) == 0
    ' "$fh/.claude/settings.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     read allowlist wrong: a rule missing (checkout/memory), the blanket projects rule back, a permissions field dropped, a secret path leaked, or not idempotent"
fi
rm -rf "$fh"

# ── notify.sh: host-independent sound/player resolution, fail-safe on no audio ──
# notify.sh emits (even under NOTIFY_DRYRUN) only when BOTH a sound and a player
# resolve, and its fallbacks depend on which freedesktop sounds / players a host
# ships. Asserting real output would false-fail on a headless box (no player) or
# one carrying only bell.oga (alert and done both fall through to bell). So we
# prove the RESOLUTION LOGIC against a self-contained toolkit root (known,
# distinct override sounds) with a minimal PATH holding a FAKE player —
# deterministic on any host — and prove the no-player path is silent success.
nb="$(mktemp -d)"; tk="$nb/tk root"        # a space in the root proves single-arg
mkdir -p "$nb/bin" "$nb/noaudio" "$tk/hooks" "$tk/sounds"
cp "$root/hooks/notify.sh" "$tk/hooks/notify.sh"
: > "$tk/sounds/alert.oga"; : > "$tk/sounds/done.oga"
# Minimal PATHs: only the interpreter + externals notify.sh needs. $nb/bin also
# carries a fake player; $nb/noaudio carries none (the headless-box case).
for b in bash dirname setsid; do
  bp="$(command -v "$b" 2>/dev/null)" && { ln -s "$bp" "$nb/bin/$b"; ln -s "$bp" "$nb/noaudio/$b"; }
done
# No real paplay/pw-play/aplay on this PATH, so the multi-word "ffplay …"
# candidate is the one that resolves; it records its argv so we can prove the
# flags word-split and the sound is passed as ONE final argument.
cat > "$nb/bin/ffplay" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$nb/argv"
EOF
chmod +x "$nb/bin/ffplay"
dry() { PATH="$nb/bin" NOTIFY_DRYRUN=1 "$tk/hooks/notify.sh" "$@"; }

# (1) alert and done resolve to distinct, KNOWN sounds via the override branch —
#     same result on any host; and the override is what wins (a fallback would
#     give a /usr/share/... path, not these).
al="$(dry alert)"; dn="$(dry done)"
if [ -n "$al" ] && [ "${al#*|}" = "$tk/sounds/alert.oga" ] \
   && [ "${dn#*|}" = "$tk/sounds/done.oga" ] && [ "$al" != "$dn" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL notify.sh      alert/done must resolve to distinct override sounds (alert=$al done=$dn)"
fi

# (2) unknown kind → silent and still exit 0 (never guesses a sound).
if [ -z "$(dry bogus)" ] && dry bogus >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL notify.sh      unknown kind must be silent and still exit 0"
fi

# (3) fail-safe: with NO player on PATH, notify.sh is silent and exits 0 — the
#     headless-box contract that keeps this portable gate green with no audio.
if [ -z "$(PATH="$nb/noaudio" NOTIFY_DRYRUN=1 "$tk/hooks/notify.sh" alert)" ] \
   && PATH="$nb/noaudio" NOTIFY_DRYRUN=1 "$tk/hooks/notify.sh" alert >/dev/null 2>&1; then
  pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL notify.sh      no audio player must degrade to silent success"
fi

# (4) the multi-word player path: ffplay is selected, word-split into its flags,
#     with the resolved sound (which contains a space) passed as ONE final arg —
#     an unquoted "$sound" or a quoted "$player" would change the recorded argv.
d="$(dry alert)"; snd="${d#*|}"; rm -f "$nb/argv"
PATH="$nb/bin" "$tk/hooks/notify.sh" alert
for i in 1 2 3 4 5; do [ -s "$nb/argv" ] && break; sleep 0.2; done
printf -- '-nodisp\n-autoexit\n-loglevel\nquiet\n%s\n' "$snd" > "$nb/argv.want"
if [ "${d%%|*}" = "ffplay" ] && diff -q "$nb/argv" "$nb/argv.want" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL notify.sh      multi-word ffplay must be selected with the sound as one final arg"
fi
rm -rf "$nb"

# ── statusline: toolkit version segment shows the version, ⚠ only when stale ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"; ln -s "$root" "$fh/.claude/agent-toolkit"
realsha="$(git -C "$root" rev-parse --short HEAD)"
printf 'v50·%s\n' "$realsha" > "$fh/.claude/agent-toolkit-version"
out_fresh="$(printf '{}' | HOME="$fh" python3 "$root/hooks/statusline.py" 2>/dev/null)"
printf 'v49·0000000\n' > "$fh/.claude/agent-toolkit-version"
out_stale="$(printf '{}' | HOME="$fh" python3 "$root/hooks/statusline.py" 2>/dev/null)"
if printf '%s' "$out_fresh" | grep -q "v50·$realsha" && ! printf '%s' "$out_fresh" | grep -q '⚠' \
   && printf '%s' "$out_stale" | grep -q '⚠'; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL statusline.py  toolkit version segment / stale ⚠ marker wrong"
fi
rm -rf "$fh"

echo "────────────────────────────────"
echo "pass: $pass  fail: $fail"
[ "$fail" -eq 0 ]

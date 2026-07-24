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

# ── guard-git: the ~/.claude exemption is per PATH, never command-wide ──
# Judged over the whole command, a read of ANY exempt path laundered a gated
# write standing beside it — the write went through with no prompt behind it,
# since ~/.claude is now an approved working directory. Each separator gets its
# own case: they are what a command is split on, so a fix that only handled &&
# would leave the others open. The last four are the same laundering by other
# spellings of home, by gluing the target onto an exempt path so a per-token
# check reads one path, and by walking into the directory first.
bash_case ask 'cat ~/.claude/agent-toolkit/README.md && echo pwned > ~/.claude/settings.json'
bash_case ask 'cat ~/.claude/agent-toolkit/README.md ; echo pwned > ~/.claude/settings.json'
bash_case ask 'cat ~/.claude/agent-toolkit/README.md | tee ~/.claude/settings.json'
bash_case ask 'cat ~/.claude/backups/x || cp /tmp/s.json ~/.claude/settings.json'
bash_case ask 'cp /tmp/a ~/.claude/agent-toolkit/x>~/.claude/settings.json'
bash_case ask 'echo pwned > ${HOME}/.claude/settings.json'
bash_case ask 'cp /tmp/s.json "$HOME"/.claude/settings.json'
bash_case ask 'cd ~/.claude && echo pwned > settings.json'
# …and the exempt paths themselves stay frictionless, including the toolkit
# checkout named WITHOUT a trailing slash — the form `cd` uses, and the one the
# gate above matches too, so both patterns must end the same way.
bash_case allow 'echo x > ~/.claude/projects/foo'
bash_case allow 'cd ~/.claude/agent-toolkit && cp a b'
bash_case allow 'cat ~/.claude/agent-toolkit/README.md && cat ~/.claude/settings.json'

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

# ── guard-config: the toolkit checkout is a free workspace; only hooks/ is gated ─
# The working-directory approval makes the whole checkout auto-writable — that is
# intended: it is the workspace. Its files (agents/*, core.md, skills/**,
# install.sh) must stay writable regardless of the payload cwd, because a
# subagent's cwd is not reliably the checkout (often the scratchpad or empty); an
# earlier cwd-keyed gate fired an un-suppressible ask on those legitimate writes.
# So the ONLY thing this hook asks on is hooks/* — the enforcement layer — and it
# asks there deterministically, cwd or no cwd. The cwd-ABSENT case is the exact
# subagent misfire we removed, so it is asserted here: a re-added cwd gate would
# fail it. Driven under a FIXTURE HOME with a symlinked checkout (never the real
# ~/.claude); the target is reached THROUGH the ~/.claude symlink, so only
# realpath matching catches it.
fh="$(cd "$(mktemp -d)" && pwd -P)"; mkdir -p "$fh/.claude"
tkco="$(cd "$(mktemp -d)" && pwd -P)"; mkdir -p "$tkco/hooks" "$tkco/agents"
ln -s "$tkco" "$fh/.claude/agent-toolkit"
gc_case() { # $1 expected, $2 file_path, $3 cwd, $4 label
  local out got
  out="$(jq -cn --arg f "$2" --arg c "$3" '{tool_name:"Write",tool_input:{file_path:$f},cwd:$c}' \
        | HOME="$fh" "$root/hooks/guard-config.sh" 2>/dev/null)"
  if [ -z "$out" ]; then got="allow"; else
    got="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo unparseable)"
  fi
  if [ "$got" = "$1" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %-14s want=%-5s got=%-5s  %s\n' guard-config.sh "$1" "$got" "$4"
  fi
}
gc_case allow "$fh/.claude/agent-toolkit/core.md"            "/proj"        "core.md, cwd OUTSIDE → allow (workspace; not cwd-gated)"
gc_case allow "$fh/.claude/agent-toolkit/core.md"            "$tkco"        "core.md, cwd INSIDE → allow (workspace)"
gc_case allow "$fh/.claude/agent-toolkit/skills/s/SKILL.md"  ""             "skills file, cwd ABSENT (subagent) → allow (the misfire we removed)"
gc_case ask   "$fh/.claude/agent-toolkit/hooks/notify.sh"    "$tkco"        "hooks file, cwd INSIDE → ask (enforcement layer)"
gc_case ask   "$fh/.claude/agent-toolkit/hooks/notify.sh"    "/proj"        "hooks file, cwd OUTSIDE → ask (enforcement layer)"
gc_case ask   "$fh/.claude/agent-toolkit/hooks/guard-git.sh" ""             "hooks file, cwd ABSENT (subagent) → ask (deterministic)"
gc_case allow "/proj/src/main.rs"                            "/proj"        "a normal repo write elsewhere → unaffected"
rm -rf "$fh" "$tkco"

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

# ── install.sh: the .env merge writes the toolkit env vars, keeping yours ─────
# Two vars are set. AGENT_TEAMS=1 turns on named teammates and SendMessage.
# MAX_SUBAGENT_SPAWN_DEPTH=3 restores the two-level DELEGATION model every agent
# definition is written around AND the one-deeper review gate a level-2 developer
# must still run — as of Claude Code 2.1.217 a subagent cannot spawn one at all by
# default, and nothing in a session announces that, so the day this var silently
# stops being written the fan-out just quietly flattens again.
# CLAUDE_CODE_ENABLE_TASKS=0 is a real switch — it turns the four Task tools off
# in favor of the older TodoWrite checklist — set here briefly, then reverted
# once a server-side flag keyed to the model turned out to be suppressing both
# families at once. A stale =0 would genuinely disable the Task tools the day
# that flag lifts, so the merge must DELETE it from a settings.json a previous
# install wrote it into, not just stop writing it. Same silent single-quoted-jq
# trap as above, so seed both the stale key and an unrelated one: one assertion
# then covers either var going missing, the stale switch surviving, and your own
# key being clobbered.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
printf '{"env":{"MY_OWN_VAR":"keep","CLAUDE_CODE_ENABLE_TASKS":"0"}}\n' > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
if jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1"
          and .env.CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH == "3"
          and (.env | has("CLAUDE_CODE_ENABLE_TASKS") | not)
          and .env.MY_OWN_VAR == "keep"' \
     "$fh/.claude/settings.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     env merge wrong: AGENT_TEAMS or MAX_SUBAGENT_SPAWN_DEPTH missing (the single-quoted-jq trap), a stale ENABLE_TASKS=0 not cleaned out, or your own .env key clobbered"
fi
rm -rf "$fh"

# ── install.sh: the three working directories, and the read rules they retire ─
# Anything outside the workspace prompts even in auto mode, which stalls a
# background agent on a human. Three directories cover it — the config dir, the
# per-uid scratchpad root every session is told to use, and this checkout (each
# ~/.claude/skills entry is a symlink into it, and access is judged on the
# resolved realpath, so the symlink directory alone is not enough). They subsume
# the five Read() rules earlier installs wrote into permissions.allow, which the
# merge must now SUBTRACT rather than merely stop writing — otherwise every
# already-installed machine keeps carrying them forever. Seed exactly that
# pre-migration file, with every permissions field populated, so one assertion
# covers every failure mode: a directory missing (the same single-quoted-jq trap
# as above), a retired rule surviving, the merge dropping fields or entries the
# user set, and the whole thing not being idempotent (ours are dropped before
# being re-appended). The directory set is matched EXACTLY rather than by
# containment, because the failure that matters here is a directory too BROAD —
# $HOME or / instead of the three — and containment would wave that through.
# Paths follow HOME; the retired rules are matched in the
# DOUBLED-leading-slash form they were written in, which is what made them
# absolute, while a working directory is a plain path and takes no such prefix.
# The seeded deny rule is asserted alongside the four carve-outs the config
# working directory obliges — those have their own case below.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
jq -n --arg cfg "$fh/.claude" --arg co "$(cd "$root" && pwd -P)" '{permissions:{
  allow: (["Bash(ls:*)"]
          + (["plugins","agents","skills"] | map("Read(/" + $cfg + "/" + . + "/**)"))
          + ["Read(/" + $cfg + "/projects/**/memory/**)", "Read(/" + $co + "/**)"]),
  deny: ["Read(//etc/shadow)"], ask: ["Bash(curl:*)"],
  additionalDirectories: ["/srv/shared"], defaultMode: "plan"}}' \
  > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
cp "$fh/.claude/settings.json" "$fh/pass1.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
if cmp -s "$fh/pass1.json" "$fh/.claude/settings.json" \
   && jq -e --arg cfg "$fh/.claude" --arg co "$(cd "$root" && pwd -P)" \
           --arg scratch "/tmp/claude-$(id -u)" '
      [$cfg, $scratch, $co] as $want_dirs
      | ((["plugins","agents","skills"] | map("Read(/" + $cfg + "/" + . + "/**)"))
         + ["Read(/" + $cfg + "/projects/**/memory/**)", "Read(/" + $co + "/**)"]) as $retired
      | (.permissions.additionalDirectories // []) as $dirs
      | (.permissions.allow // []) as $got
      | ($dirs | sort) == ((["/srv/shared"] + $want_dirs) | sort)
        and ($got - $retired) == $got
        and ($got | index("Bash(ls:*)")) != null
        and .permissions.deny == ["Read(//etc/shadow)",
                                  "Read(/" + $cfg + "/.credentials.json)",
                                  "Read(/" + $cfg + "/settings*.json)",
                                  "Read(/" + $cfg + "/backups/settings.json.*)",
                                  "Read(/" + $cfg + "/backups/.claude.json.backup.*)"]
        and .permissions.ask == ["Bash(curl:*)"]
        and .permissions.defaultMode == "auto"
    ' "$fh/.claude/settings.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     working directories wrong: one missing or too broad (config/scratchpad/checkout), a retired Read() rule left behind, a permissions field or entry dropped, duplicated, or not idempotent"
fi
rm -rf "$fh"

# ── …and an allowlist that was nothing BUT those retired rules leaves no husk ──
# The cleanup subtracts from a list it may empty, so without dropping the key a
# migrated settings.json (and every fresh one) would carry a meaningless allow:[].
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
jq -n --arg cfg "$fh/.claude" --arg co "$(cd "$root" && pwd -P)" '{permissions:{allow:
  ((["plugins","agents","skills"] | map("Read(/" + $cfg + "/" + . + "/**)"))
   + ["Read(/" + $cfg + "/projects/**/memory/**)", "Read(/" + $co + "/**)"])}}' \
  > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
if jq -e '(.permissions | has("allow")) | not' "$fh/.claude/settings.json" >/dev/null 2>&1; then
  pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     an allowlist emptied by the migration must be removed, not left as allow:[]"
fi
rm -rf "$fh"

# ── …and the reads that working directory must NOT hand over ──
# Approving ~/.claude wholesale approves a read of .credentials.json with it — and
# of settings*.json (settings.json AND the machine-local settings.local.json),
# which on another machine carry MCP tokens or API keys in their env block, and of
# the historical copies in backups/ (settings.json.* this installer writes, and
# .claude.json.backup.* Claude Code writes, which holds the mcpServers tokens). A
# deny rule is evaluated BEFORE the working-directory check, so four entries close
# them. Seed a deny rule of your own and install twice, so a single assertion
# covers any of the four missing entirely (the single-quoted-jq trap again), a
# leading slash not DOUBLED — a single slash anchors the pattern at the settings
# dir where it matches nothing, leaving the file readable while the rule LOOKS
# present — your own entry clobbered, ours appended a second time on re-run, and
# the list widened beyond those four (each backups rule names a filename glob,
# never backups/ wholesale, which holds unrelated files). settings*.json widens to
# settings.local.json without catching unrelated JSON like stats-cache.json — the
# literal settings prefix cannot match it. Read-tool only by design: the doctor
# and the update-config skill reach settings through jq in Bash, which no rule
# here touches. Matched exactly rather than by containment, because both failures
# that matter are entries missing or extra.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
printf '{"permissions":{"deny":["Read(//etc/shadow)"]}}\n' > "$fh/.claude/settings.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
cp "$fh/.claude/settings.json" "$fh/pass1.json"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
if cmp -s "$fh/pass1.json" "$fh/.claude/settings.json" \
   && jq -e --arg cfg "$fh/.claude" '
      ((.permissions.deny // []) | sort)
        == ((["Read(//etc/shadow)",
              "Read(/" + $cfg + "/.credentials.json)",
              "Read(/" + $cfg + "/settings*.json)",
              "Read(/" + $cfg + "/backups/settings.json.*)",
              "Read(/" + $cfg + "/backups/.claude.json.backup.*)"]) | sort)
    ' "$fh/.claude/settings.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     deny rules wrong (credentials / settings*.json / backups/settings.json.* / backups/.claude.json.backup.*): one missing, single-slashed (anchors at the settings dir, matching nothing), duplicated on re-run, your own deny entry clobbered, or the deny list widened"
fi
rm -rf "$fh"

# ── install.sh: the settings.json it WRITES carries the toolkit's full wiring ──
# Every install assertion above reads the TOP of the merge program (.env,
# .permissions, .enabledPlugins) — which is exactly why they are not enough. A
# balanced apostrophe PAIR anywhere in that single-quoted jq program truncates it
# there (bash -n stays happy — see the NB above desired_settings): jq is handed a
# VALID but partial program, emits a partial config, and install.sh writes it.
# Put the pair below the lines those assertions read and the statusline plus
# EVERY guard hook vanish — publish gate, config gate, Linear gate, reaper — with
# the suite green, the install exiting 0, and the doctor green too (its path
# check only validates paths it FINDS in settings, so a gutted one gives it
# nothing to check). Hence this assertion on the TAIL of the program.
#
# The whole TRIPLE is asserted — event → matcher → script (and async) — matched
# EXACTLY, because each part is load-bearing and each breaks silently on its
# own. Asserting event NAMES only, which this used to do, is vacuous: it stays
# green when "Bash" becomes "Bash " and guard-git.sh never sees a git push
# again, when the matcher is dropped so a guard fires on every tool, and when
# guard-git.sh and guard-config.sh swap places between two PreToolUse entries —
# the publish gate is gone in all three, with install exiting 0 and the doctor
# green. It also could not tell notify.sh done wired to Notification from the
# right way round.
# The table below is written out here rather than derived from install.sh —
# derived (from its source text, from its output, either way), it would move
# WITH any mutation of the installer and assert nothing. The installer's own
# TOOLKIT_WIRING declaration is what the doctor checks a machine against; this
# is the independent statement of the same contract, so the two are compared by
# running them against each other. A hook added there therefore has to be added
# here too: that is the assertion doing its job, not a chore.
# HOME is fresh, so every hook in that file is ours; a foreign one could not
# skew either side.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
b="$fh/.claude/agent-toolkit"
got_wiring="$(jq -Sc '
  [ (.hooks // {}) | to_entries[] as $ev | $ev.value[] as $e | ($e.hooks // [])[] as $h
    | select(($h.command // "") | test("agent-toolkit"))
    | {event: $ev.key, matcher: ($e.matcher // ""), command: ($h.command // ""),
       async: ($h.async // false)} ] | sort' \
  "$fh/.claude/settings.json" 2>/dev/null)"
want_wiring="$(jq -Scn --arg b "$b" '[
  {event:"SessionStart", matcher:"startup|resume|clear", command:($b+"/install.sh --sync"),        async:false},
  {event:"PreToolUse",   matcher:"Bash",                 command:($b+"/hooks/guard-git.sh"),       async:false},
  {event:"PreToolUse",   matcher:"Write|Edit|NotebookEdit", command:($b+"/hooks/guard-config.sh"), async:false},
  {event:"PreToolUse",   matcher:"mcp__linear.*",        command:($b+"/hooks/guard-linear.sh"),    async:false},
  {event:"PostToolUse",  matcher:"Write|Edit",           command:($b+"/hooks/sync-on-skill-edit.sh"), async:false},
  {event:"PostToolUse",  matcher:"Write|Edit",           command:($b+"/hooks/format-on-edit.sh"),  async:true},
  {event:"SubagentStop", matcher:"",                     command:($b+"/hooks/reap-managed.sh"),    async:false},
  {event:"SessionEnd",   matcher:"",                     command:($b+"/hooks/reap-managed.sh"),    async:false},
  {event:"Notification", matcher:"",                     command:($b+"/hooks/notify.sh alert"),    async:false},
  {event:"Stop",         matcher:"",                     command:($b+"/hooks/notify.sh done"),     async:false}
] | sort')"
sl_cmd="$(jq -r '.statusLine.command // ""' "$fh/.claude/settings.json" 2>/dev/null)"
if [ "$got_wiring" = "$want_wiring" ] && [ "$sl_cmd" = "$b/hooks/statusline.py" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL install.sh     installed wiring is not exactly event→matcher→script (a hook missing, a matcher changed, two scripts swapped, an async flag flipped, or the statusline gone)"
  echo "                    want: $want_wiring"
  echo "                    got:  $got_wiring"
  echo "                    statusLine: $sl_cmd (want $b/hooks/statusline.py)"
fi
rm -rf "$fh"

# ── install.sh: the doctor notices a hook that went missing from settings.json ─
# The case the doctor exists for is a machine whose settings.json quietly lost a
# hook — a hand-edit, a partial merge, a restored backup — because from then on
# git push runs with NO publish gate. The requirement it checks against used to
# be scraped out of install.sh's own source text and was event names only, which
# fails twice over: reformat one merge line and that event drops out of the
# requirement (still green), and an entry that loses just guard-git.sh keeps the
# PreToolUse name alive (still green). So tamper with the two ways that leave
# the event standing and require the doctor to name what is gone. --sync also
# reports the file as stale here, and exits nonzero either way, so the exit code
# proves nothing on its own — the wiring message is what is asserted.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
tamper() { jq "$1" "$fh/.claude/settings.json" > "$fh/t.json" && mv "$fh/t.json" "$fh/.claude/settings.json"; }
tamper '.hooks.PreToolUse |= map(select(([.hooks[]?.command // ""] | any(test("guard-git"))) | not))'
out_drop="$(HOME="$fh" "$root/install.sh" --sync 2>&1)"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1        # repair, then break it differently
tamper '.hooks.PreToolUse |= map(if .matcher == "Bash" then .matcher = "Bash " else . end)'
out_matcher="$(HOME="$fh" "$root/install.sh" --sync 2>&1)"
names_it() { case "$1" in *"missing toolkit wiring"*"guard-git.sh"*) return 0 ;; *) return 1 ;; esac; }
if names_it "$out_drop" && names_it "$out_matcher"; then pass=$((pass + 1)); else
  fail=$((fail + 1))
  echo "FAIL install.sh     the doctor did not name the dropped/mis-matched guard-git.sh hook"
  echo "                    dropped-hook run: $out_drop"
  echo "                    changed-matcher run: $out_matcher"
fi
rm -rf "$fh"

# ── install.sh: a jq merge that ABORTS fails loudly, never "already current" ───
# If desired_settings aborts — a pre-existing permissions.allow that is a string,
# not an array, makes jq exit non-zero with empty output — the old guard read that
# empty output as already-current: green doctor, exit 0, a fresh version stamp, and
# NOTHING applied. Assert it now says "merge failed", never "already current", and
# leaves no stamp. (The mutation is restoring the old if [ -n "$new" ] guard: then
# it reports already-current, and this case catches it.)
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
printf '{"permissions":{"allow":"not-an-array"}}\n' > "$fh/.claude/settings.json"
out="$(HOME="$fh" "$root/install.sh" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -qi "merge failed" \
   && ! printf '%s' "$out" | grep -qi "already current" \
   && [ ! -s "$fh/.claude/agent-toolkit-version" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     a jq merge that aborts must fail loudly (not report already-current) and must not stamp (rc=$rc)"
fi
rm -rf "$fh"

# ── install.sh: a $HOME containing a space keeps the doctor green ──────────────
# The doctor stripped a wired command to its executable with ${cmd%% *} and scanned
# the pointer import with ^@/[^ ]+ — both split at the FIRST space, so a $HOME with
# a space truncated every wired path and every hook read as missing: 12 false
# errors, exit 1, no stamp, and it lands in session context every SessionStart.
# Install under a spaced HOME and require a green, stamped doctor.
tmp="$(mktemp -d)"; fh="$tmp/home dir"; mkdir -p "$fh/.claude"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ -s "$fh/.claude/agent-toolkit-version" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     a \$HOME with a space breaks the doctor (rc=$rc) — a wired-hook or pointer path split at the space"
fi
rm -rf "$tmp"

# ── install.sh: a foreign hook with args (no .sh/.py) is not false-flagged ─────
# The spaced-$HOME fix scopes its .sh/.py suffix-matching to $STABLE commands, so a
# FOREIGN hook keeps the old first-space arg-strip — else an existing executable
# plus an arg and no extension ("/usr/bin/env X") would read as missing. Seed
# exactly that and require the doctor not to name it (green, stamped). $STABLE
# commands still work, so this is distinct from the spaced-HOME case above.
feh="$(command -v env)"
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
jq -n --arg c "$feh marker-arg" '{hooks:{Stop:[{hooks:[{type:"command",command:$c}]}]}}' \
  > "$fh/.claude/settings.json"
out="$(HOME="$fh" "$root/install.sh" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && [ -s "$fh/.claude/agent-toolkit-version" ] \
   && ! printf '%s' "$out" | grep -qF "$feh marker-arg"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     a foreign hook with args and no .sh/.py extension must not be reported missing (rc=$rc)"
fi
rm -rf "$fh"

# ── install.sh: the doctor flags pr-review-toolkit enabled-but-not-installed ───
# install.sh ENABLES the plugin in settings, but enabling is not installing (that
# needs `claude plugin install`). The review gate every developer/reviewer agent
# spawns IS this plugin's agents, so absent it there is no gate — an unknown
# subagent type. Drive both states against a fixture installed_plugins.json (never
# the real cache): absent → the doctor names it and points at the fix; present →
# silent about the plugin.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/plugins"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1                 # no installed_plugins.json yet
out_absent="$(HOME="$fh" "$root/install.sh" --sync 2>&1)"
printf '{"plugins":{"pr-review-toolkit@claude-plugins-official":[{"scope":"user"}]}}\n' \
  > "$fh/.claude/plugins/installed_plugins.json"
out_present="$(HOME="$fh" "$root/install.sh" --sync 2>&1)"
if printf '%s' "$out_absent" | grep -q "pr-review-toolkit@claude-plugins-official is enabled but not installed" \
   && ! printf '%s' "$out_present" | grep -qi "pr-review-toolkit.*not installed"; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     doctor must flag pr-review-toolkit enabled-but-not-installed, and go silent once installed"
fi
rm -rf "$fh"

# ── install.sh: --sync applies agents+skills, so it must stamp the version too ─
# --sync IS the ordinary edit-commit-new-session path (SessionStart runs it): it
# re-links skills and re-copies agents, so the "are my changes applied?" light must
# clear on it, not wait for a manual full install. Full-install first (clean
# settings), drop the stamp, then --sync, and the stamp must come back. The gate
# stays tk_problems, so a stale settings.json would still hold it — but here it is
# current, so the only thing that could withhold the stamp is the old MODE=full gate.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude"
HOME="$fh" "$root/install.sh" >/dev/null 2>&1
rm -f "$fh/.claude/agent-toolkit-version"
HOME="$fh" "$root/install.sh" --sync >/dev/null 2>&1
if [ -s "$fh/.claude/agent-toolkit-version" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     --sync must stamp the version (it re-applies agents+skills), not leave the freshness light stale"
fi
rm -rf "$fh"

# ── install.sh: a moved checkout drops its OLD write-approved dir ──────────────
# additionalDirectories lists the checkout so agents can write in it; the merge
# used to subtract only the CURRENT checkout before re-adding, so moving the
# checkout (a workflow the README advertises) left the OLD path write-approved
# forever, pointing at a location that may later hold an unrelated project. Copy
# the toolkit to A and B, install from each under one HOME (the stable symlink
# carries A forward as $prevroot), and assert the final additionalDirectories
# carries B and the user dir, never A. HOME is made physical so it matches the
# pwd -P ROOT each copy computes.
fh="$(cd "$(mktemp -d)" && pwd -P)"; mkdir -p "$fh/.claude"
printf '{"permissions":{"additionalDirectories":["/srv/mine"]}}\n' > "$fh/.claude/settings.json"
mk_copy() { mkdir -p "$1"; for p in install.sh install-skills.sh core.md CLAUDE.md hooks agents skills; do cp -a "$root/$p" "$1/"; done; }
A="$fh/checkout-A"; B="$fh/checkout-B"; mk_copy "$A"; mk_copy "$B"
HOME="$fh" "$A/install.sh" >/dev/null 2>&1
HOME="$fh" "$B/install.sh" >/dev/null 2>&1
if jq -e --arg a "$A" --arg b "$B" '
     (.permissions.additionalDirectories // []) as $d
     | ($d | any(. == $b)) and ($d | any(. == $a) | not)
       and ($d | any(. == "/srv/mine"))' \
     "$fh/.claude/settings.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL install.sh     a moved checkout must drop its old additionalDirectories entry, keep the new one and user-added dirs"
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
# A dry-run line is "player|sound|xdg_runtime_dir", so the sound is the MIDDLE
# field — strip the leading player AND the trailing runtime dir. Neither a
# mktemp path nor /run/user/<euid> contains a "|", so the outer fields are
# unambiguous; parse through these so a future field can't silently shift them.
sound_of() { local rest="${1#*|}"; printf '%s\n' "${rest%|*}"; }
xdg_of() { printf '%s\n' "${1##*|}"; }

# (1) alert and done resolve to distinct, KNOWN sounds via the override branch —
#     same result on any host; and the override is what wins (a fallback would
#     give a /usr/share/... path, not these).
al="$(dry alert)"; dn="$(dry done)"
if [ -n "$al" ] && [ "$(sound_of "$al")" = "$tk/sounds/alert.oga" ] \
   && [ "$(sound_of "$dn")" = "$tk/sounds/done.oga" ] && [ "$al" != "$dn" ]; then pass=$((pass + 1)); else
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
d="$(dry alert)"; snd="$(sound_of "$d")"; rm -f "$nb/argv"
PATH="$nb/bin" "$tk/hooks/notify.sh" alert
for i in 1 2 3 4 5; do [ -s "$nb/argv" ] && break; sleep 0.2; done
printf -- '-nodisp\n-autoexit\n-loglevel\nquiet\n%s\n' "$snd" > "$nb/argv.want"
if [ "${d%%|*}" = "ffplay" ] && diff -q "$nb/argv" "$nb/argv.want" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL notify.sh      multi-word ffplay must be selected with the sound as one final arg"
fi

# (5) the bare-environment contract: every case above invokes notify.sh with a
#     session env it never actually gets as a hook, and that gap is how a mute
#     notifier shipped — no $XDG_RUNTIME_DIR, so the player fails "Connection
#     refused" into the /dev/null redirect with no error anywhere. So run it the
#     way a hook does (env -i, only the minimal PATH above) and assert it
#     resolves the runtime dir itself, derived independently via id -u — plus
#     that a session which DOES provide one wins, never clobbered by the default.
bare="$(env -i PATH="$nb/bin" NOTIFY_DRYRUN=1 "$tk/hooks/notify.sh" alert)"
given="$(env -i PATH="$nb/bin" XDG_RUNTIME_DIR="$nb/session-xdg" NOTIFY_DRYRUN=1 "$tk/hooks/notify.sh" alert)"
if [ "$(xdg_of "$bare")" = "/run/user/$(id -u)" ] \
   && [ "$(xdg_of "$given")" = "$nb/session-xdg" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL notify.sh      a bare hook env must resolve XDG_RUNTIME_DIR to /run/user/<euid> and a provided one must survive (bare=$bare given=$given)"
fi

# (6) aplay decodes only WAV — never Ogg. On an alsa-only host (aplay the SOLE
#     player) a .oga sound must fall through to silent success: choosing aplay
#     there errors into the /dev/null redirect below — the exact mute-notifier
#     regression, invisible while the doctor still sees a player on PATH. Yet a
#     .wav sound on that same host MUST still resolve to aplay (it can decode
#     WAV). A toolkit root with alert=.oga and done=.wav proves both directions,
#     so neither "always skip aplay" nor "always accept aplay" can pass.
ak="$nb/alsa-tk"; mkdir -p "$ak/hooks" "$ak/sounds" "$nb/alsa"
cp "$root/hooks/notify.sh" "$ak/hooks/notify.sh"
: > "$ak/sounds/alert.oga"; : > "$ak/sounds/done.wav"
for b in bash dirname setsid; do
  bp="$(command -v "$b" 2>/dev/null)" && ln -s "$bp" "$nb/alsa/$b"
done
printf '#!/bin/sh\nexit 0\n' > "$nb/alsa/aplay"; chmod +x "$nb/alsa/aplay"
oga_line="$(PATH="$nb/alsa" NOTIFY_DRYRUN=1 "$ak/hooks/notify.sh" alert)"
wav_line="$(PATH="$nb/alsa" NOTIFY_DRYRUN=1 "$ak/hooks/notify.sh" done)"
if [ -z "$oga_line" ] && PATH="$nb/alsa" NOTIFY_DRYRUN=1 "$ak/hooks/notify.sh" alert >/dev/null 2>&1 \
   && [ "${wav_line%%|*}" = "aplay" ] && [ "$(sound_of "$wav_line")" = "$ak/sounds/done.wav" ]; then
  pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL notify.sh      aplay must be skipped for .oga (silent) yet chosen for .wav (oga=$oga_line wav=$wav_line)"
fi
rm -rf "$nb"

# ── install.sh: the doctor's sound check matches notify.sh's aplay-can't-Ogg rule ─
# notify.sh case 6 above proves the RUNTIME skips aplay for the .oga freedesktop
# fallbacks (aplay decodes only WAV); this proves the DOCTOR now agrees. An
# aplay-ONLY host with the default .oga sounds plays NOTHING, yet the old doctor
# warned only when ALL of paplay/pw-play/ffplay/aplay were absent — so it stayed
# silent and reported sound wired: the same doctor-vs-reality blind spot, one
# layer up. The doctor now mirrors notify.sh's coarse decision — aplay alone is
# enough only if the toolkit ships .wav overrides for BOTH notify kinds. Drive the
# REAL doctor with a PATH whose only audio player is a fake aplay: the host's real
# players are masked by mirroring $PATH minus the four, so this is hermetic even
# here where all four are installed. A fixture checkout whose sounds/ we control
# gives the with/without-.wav states without touching the real repo; a fake ffplay
# added last is the richer-player case. Three states, one fixture: aplay+no-wav
# warns, aplay+both-wav silent, ffplay silent — so neither "aplay always counts"
# (the bug) nor "aplay never counts" can pass.
sc="$(mktemp -d)"; scbin="$sc/bin"; mkdir -p "$scbin"
IFS=: read -ra scpath <<< "$PATH"
for d in "${scpath[@]}"; do
  [ -d "$d" ] || continue
  ln -s "$d"/* "$scbin/" 2>/dev/null || true   # first-wins union of the real PATH
done
# Drop the four audio players (and any literal-'*' link an empty PATH dir left),
# so command -v finds exactly the fake players we inject below and nothing else.
rm -f "$scbin/paplay" "$scbin/pw-play" "$scbin/ffplay" "$scbin/aplay" "$scbin/*"
printf '#!/bin/sh\nexit 0\n' > "$scbin/aplay"; chmod +x "$scbin/aplay"   # command -v only checks it exists+x
sctk="$sc/tk"; mkdir -p "$sctk"
for p in install.sh install-skills.sh core.md CLAUDE.md hooks agents skills; do cp -a "$root/$p" "$sctk/"; done
sc_run() { rm -rf "$sc/home"; mkdir -p "$sc/home/.claude"; PATH="$scbin" HOME="$sc/home" "$sctk/install.sh" 2>&1; }
sc_warns() { case "$1" in *"only aplay is installed"*) return 0 ;; *) return 1 ;; esac; }
out_nowav="$(sc_run)"
mkdir -p "$sctk/sounds"; : > "$sctk/sounds/alert.wav"; : > "$sctk/sounds/done.wav"
out_wav="$(sc_run)"
printf '#!/bin/sh\nexit 0\n' > "$scbin/ffplay"; chmod +x "$scbin/ffplay"
out_ffplay="$(sc_run)"
if sc_warns "$out_nowav" && ! sc_warns "$out_wav" && ! sc_warns "$out_ffplay"; then
  pass=$((pass + 1)); else
  fail=$((fail + 1))
  echo "FAIL install.sh     doctor sound check: aplay-only+no-wav must warn, but .wav overrides or a richer player must stay silent"
fi
rm -rf "$sc"

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

# ── statusline: freshness FAILS SAFE — a `?`, never a confident clean stamp — ──
# ── when the rev-parse that verifies HEAD times out or errors ─────────────────
# The bug this pins is the inverse: a swallowed TimeoutExpired left NO marker, so
# the stamp asserted "your commits are applied" on a machine that had not re-run
# install.sh — the exact failure the light exists to catch, silently inverted.
# Only a POSITIVE sha match may render clean; a timeout/error must show `?` (never
# a false clean, never a false ⚠). Fake gits make both directions deterministic
# and hermetic — a real git that happened to be slow can't skew it — and the
# timeout one uses exec-sleep so subprocess's SIGKILL leaves nothing behind.
fh="$(mktemp -d)"; mkdir -p "$fh/.claude" "$fh/bin"; ln -s "$root" "$fh/.claude/agent-toolkit"
printf 'v50·abc1234\n' > "$fh/.claude/agent-toolkit-version"
run_sl() { printf '{}' | PATH="$fh/bin:$PATH" HOME="$fh" python3 "$root/hooks/statusline.py" 2>/dev/null; }
printf '#!/bin/sh\nexec sleep 0.5\n' > "$fh/bin/git"; chmod +x "$fh/bin/git"    # every rev-parse times out
out_to="$(run_sl)"
printf '#!/bin/sh\necho abc1234\n' > "$fh/bin/git"; chmod +x "$fh/bin/git"      # rev-parse returns the recorded sha
out_fresh2="$(run_sl)"
if printf '%s' "$out_to"     | grep -q '⬡ v50·abc1234' \
   && printf '%s' "$out_to"     | grep -q '?'  && ! printf '%s' "$out_to"     | grep -q '⚠' \
   && printf '%s' "$out_fresh2" | grep -q '⬡ v50·abc1234' \
   && ! printf '%s' "$out_fresh2" | grep -q '?' && ! printf '%s' "$out_fresh2" | grep -q '⚠'; then
  pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL statusline.py  freshness must show '?' on git timeout/error and clean only on a verified match (timeout=$out_to fresh=$out_fresh2)"
fi
rm -rf "$fh"

echo "────────────────────────────────"
echo "pass: $pass  fail: $fail"
[ "$fail" -eq 0 ]

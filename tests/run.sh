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

# ── spawn-managed + reap-managed: dead-owner procs reaped, live/unknown spared ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/sessions"
p_dead_owner="$(HOME="$fh" CLAUDE_CODE_SESSION_ID=gone-session "$root/hooks/spawn-managed.sh" -- sleep 300 | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+')"
p_live_owner="$(HOME="$fh" CLAUDE_CODE_SESSION_ID=live-session "$root/hooks/spawn-managed.sh" -- sleep 300 | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+')"
p_unknown="$(HOME="$fh" CLAUDE_CODE_SESSION_ID= "$root/hooks/spawn-managed.sh" -- sleep 300 | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+')"
printf '{"pid":99999999,"session":"s","cmd":"x","started":"t"}' > "$fh/.claude/managed-procs/99999999.json"
printf '{"pid":%d,"sessionId":"live-session"}' "$$" > "$fh/.claude/sessions/$$.json"
HOME="$fh" "$root/hooks/reap-managed.sh"; HOME="$fh" "$root/hooks/reap-managed.sh"
for i in 1 2 3 4 5; do kill -0 "$p_dead_owner" 2>/dev/null || break; sleep 0.2; done
if ! kill -0 "$p_dead_owner" 2>/dev/null && [ ! -e "$fh/.claude/managed-procs/$p_dead_owner.json" ]; then
  pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL reap-managed   dead-owner process not reaped"
fi
if kill -0 "$p_live_owner" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   live-owner process was killed"
fi
if kill -0 "$p_unknown" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   unknown-owner process was killed (must be fail-safe)"
fi
if [ ! -e "$fh/.claude/managed-procs/99999999.json" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   dead-pid entry not pruned"
fi
kill "$p_live_owner" "$p_unknown" 2>/dev/null; rm -rf "$fh"

# ── reap-managed fail-safe: no sessions registry → never kill (liveness unknowable) ──
fh="$(mktemp -d)"
p_nosessions="$(HOME="$fh" CLAUDE_CODE_SESSION_ID=gone-session "$root/hooks/spawn-managed.sh" -- sleep 300 | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+')"
HOME="$fh" "$root/hooks/reap-managed.sh"; HOME="$fh" "$root/hooks/reap-managed.sh"
if kill -0 "$p_nosessions" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   killed a process with NO sessions registry (must fail safe)"
fi
kill "$p_nosessions" 2>/dev/null; rm -rf "$fh"

# ── reap-managed: recycled pid (start time mismatch) is pruned, never signalled ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/managed-procs" "$fh/.claude/sessions"
p_innocent="$(setsid sleep 300 >/dev/null 2>&1 & echo $!)"
printf '{"pid":%d,"session":"gone-session","starttime":"1"}' "$p_innocent" > "$fh/.claude/managed-procs/$p_innocent.json"
printf '{"pid":%d,"sessionId":"live-session"}' "$$" > "$fh/.claude/sessions/$$.json"
HOME="$fh" "$root/hooks/reap-managed.sh"; HOME="$fh" "$root/hooks/reap-managed.sh"
if kill -0 "$p_innocent" 2>/dev/null && [ ! -e "$fh/.claude/managed-procs/$p_innocent.json" ]; then
  pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   recycled-pid entry must be pruned WITHOUT signalling the process"
fi
kill "$p_innocent" 2>/dev/null; rm -rf "$fh"

# ── reap-managed: TERM is not escalated to KILL inside the grace window ──
fh="$(mktemp -d)"; mkdir -p "$fh/.claude/sessions"
p_grace="$(HOME="$fh" CLAUDE_CODE_SESSION_ID=gone-session "$root/hooks/spawn-managed.sh" -- sh -c 'trap "" TERM; sleep 300' | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+')"
printf '{"pid":%d,"sessionId":"live-session"}' "$$" > "$fh/.claude/sessions/$$.json"
HOME="$fh" "$root/hooks/reap-managed.sh"; sleep 0.3; HOME="$fh" "$root/hooks/reap-managed.sh"
if kill -0 "$p_grace" 2>/dev/null; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL reap-managed   SIGKILLed inside the grace window (no time to shut down)"
fi
kill -KILL -- "-$p_grace" 2>/dev/null; rm -rf "$fh"

# ── spawn-managed: a command with quotes/backslashes/newlines stays valid JSON ──
fh="$(mktemp -d)"
p_json="$(HOME="$fh" CLAUDE_CODE_SESSION_ID=s "$root/hooks/spawn-managed.sh" -- sh -c 'sleep 300 # a "quoted" \back\slash
newline' | grep -oE 'pid [0-9]+' | grep -oE '[0-9]+')"
if jq -e '.pid' "$fh/.claude/managed-procs/$p_json.json" >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL spawn-managed  registry entry is not valid JSON for a tricky command"
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

echo "────────────────────────────────"
echo "pass: $pass  fail: $fail"
[ "$fail" -eq 0 ]

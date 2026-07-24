---
name: toolkit-maintenance
description: Change the agent-toolkit itself — add or revise a skill, hook, agent definition, core.md rule, or the installer/statusline — and land it so every machine picks it up. Use when codifying a session learning ("add this to the toolkit", "remember this globally", "make this a rule/skill everywhere"), when editing anything in the agent-toolkit repo (core.md, skills/, agents/, hooks/, install.sh), or when the SessionStart doctor reports the toolkit broken.
---

# Toolkit maintenance

The toolkit is a repo with the same discipline as production code — edit → verify → review → gated commit/push — because its consumers are every future session on every machine. Device config reaches it only through the `~/.claude/agent-toolkit` symlink; `readlink` that for the real checkout.

**Dogfood it.** You run *on* this toolkit while you build it, so any session carries a standing lens: notice the friction you hit, the gate that was missing, the rule that would have helped *this* task — and fold it back the same session (surface it to the user, land it under the gates below). Working *inside* this repo sharpens the lens further, but the best source of improvements is simply using the thing. Don't let a lesson evaporate because the task was "done."

## Where a change lands (first decision, in order)

- **Always-true principle, every task** → `core.md` — a sentence, not a section; it loads every session, so it must stay small.
- **Task procedure or growing reference** → a skill (`skill-authoring` owns the craft and the role-placement rule).
- **An agent's identity, loop, or boundary** → its definition (`agents/<role>.md`); its exclusive tools live in the frontmatter `tools:` allowlist.
- **Mechanical enforcement** — must hold even if the model forgets → a hook under `hooks/` **plus a case in `tests/run.sh`** (an agent's tool boundary is already mechanical — prefer the allowlist over a new hook).
- **Wiring** — what `settings.json` points at → `install.sh` only; never hand-edit `~/.claude/settings.json` for toolkit-managed entries. The Read tool is denied on it and on its backups (README § Enforcement), so inspect it with `jq` in Bash — and since Edit refuses a file it has not read, that deny is also what makes the hand-edit mechanical rather than merely asked-for.
- **Device-local only** → not the toolkit's business; `~/.claude/CLAUDE.md` stays a one-line pointer.

One home: never duplicate a rule across these layers — link to where it lives.

## Verify before landing

- **Skill added/renamed:** sync into `~/.claude/skills` is automatic (SessionStart + on-skill-edit hooks) — confirm with `ls -l ~/.claude/skills/<name>`; tune the trigger description with `/skill-creator` eval when firing accuracy matters.
- **Agent added/renamed:** agents are **copied** into `~/.claude/agents/` by `install.sh` (sync at SessionStart; the manifest prunes removed names) — run `./install.sh` after editing to make it live now, and confirm with `ls ~/.claude/agents/`.
- **Hook changed:** extend `tests/run.sh` with the new case and run it — all green before commit. For the statusline, pipe a sample status JSON through `hooks/statusline.py`.
  - **A fail-safe hook with an optional dependency** (an audio player, a sound file, an external binary) is tested for its *resolution logic*, not its side effect: drive it against a controlled fixture — a temp toolkit root with known files, a minimal `PATH` holding a fake binary — so the assertion is deterministic on any host, and skip or neutralize the part that genuinely needs the dependency when it's absent. Strip the environment too (`env -i` with that minimal `PATH`) — a hook's context is bare, not your shell's, so a fixture that inherits yours can't see what the hook will. The portable gate must stay green on a headless box with no audio at all.
  - **Probing a guard by hand: keep the payload off the command line.** Every guard reads its payload from stdin and nothing from argv, so put it in a file and redirect: write `$SCRATCH/p.json` with the **Write tool** (`$SCRATCH` is `/tmp/claude-$(id -u)`, a working directory), then `hooks/guard-git.sh < "$SCRATCH/p.json"`. Piped inline — `echo '{"tool_name":"Bash","tool_input":{"command":"echo x > ~/.claude/settings.json"}}' | hooks/guard-git.sh` — the probe prompts for permission instead: the dangerous-looking text is *data* inside a quoted argument, but neither `guard-git.sh` (a quoted mention of a gated command can trip an ask — fail-safe by design, stated at its head) nor the auto-mode classifier can tell a mention from an invocation without parsing shell quoting, and anything that tried to would be the exact bypass an attacker wants. Staging it in a shell variable does not help — the assignment line carries the same text, and guard-git answers `ask` to that too; the payloads in `tests/run.sh` live inside the file for the same reason, which is why running the suite never prompts. Redirection is the right fix rather than a permission rule because it adds no rule and loosens nothing: a real `echo x > ~/.claude/settings.json` still trips both layers exactly as before. The tempting rule does not work anyway — rules match the pipeline's segments and the flagged text sits in the `echo` segment, so the only one that would silence it is `Bash(echo:*)`, which *would* wave a genuine redirect through.
- **Wiring changed:** `./install.sh --dry-run` to preview the exact device-config diff, then `./install.sh` with the user's approval (it writes `~/.claude`).
- **Anything renamed/removed:** grep the whole repo for the retired name (core.md's sweep-on-rename) — README and `orchestrating-subagents`' roster are the usual stragglers.

## Land and propagate

- Commit in the toolkit repo under the standing gates (per-action approval, message verbatim + diff summary, no AI attribution) — then remind the user to approve a **push**: other machines only receive the change after it's on origin.
- On another machine, `git pull` in the checkout is the whole upgrade — the next SessionStart re-links skills and re-checks wiring automatically; a brand-new machine is one `git clone` + `./install.sh`.
- The SessionStart doctor prints `agent-toolkit doctor: ✗ …` into session context when something's broken — fix via `./install.sh`, never by hand-editing settings; it also flags a missing `jq` (the guard hooks fail open without it).

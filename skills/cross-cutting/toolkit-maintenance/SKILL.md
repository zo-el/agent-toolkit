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
- **Wiring** — what `settings.json` points at → `install.sh` only; never hand-edit `~/.claude/settings.json` for toolkit-managed entries.
- **Device-local only** → not the toolkit's business; `~/.claude/CLAUDE.md` stays a one-line pointer.

One home: never duplicate a rule across these layers — link to where it lives.

## Verify before landing

- **Skill added/renamed:** sync into `~/.claude/skills` is automatic (SessionStart + on-skill-edit hooks) — confirm with `ls -l ~/.claude/skills/<name>`; tune the trigger description with `/skill-creator` eval when firing accuracy matters.
- **Agent added/renamed:** agents are **copied** into `~/.claude/agents/` by `install.sh` (sync at SessionStart; the manifest prunes removed names) — run `./install.sh` after editing to make it live now, and confirm with `ls ~/.claude/agents/`.
- **Hook changed:** extend `tests/run.sh` with the new case and run it — all green before commit. For the statusline, pipe a sample status JSON through `hooks/statusline.py`.
- **Wiring changed:** `./install.sh --dry-run` to preview the exact device-config diff, then `./install.sh` with the user's approval (it writes `~/.claude`).
- **Anything renamed/removed:** grep the whole repo for the retired name (core.md's sweep-on-rename) — README and `orchestrating-subagents`' roster are the usual stragglers.

## Land and propagate

- Commit in the toolkit repo under the standing gates (per-action approval, message verbatim + diff summary, no AI attribution) — then remind the user to approve a **push**: other machines only receive the change after it's on origin.
- On another machine, `git pull` in the checkout is the whole upgrade — the next SessionStart re-links skills and re-checks wiring automatically; a brand-new machine is one `git clone` + `./install.sh`.
- The SessionStart doctor prints `agent-toolkit doctor: ✗ …` into session context when something's broken — fix via `./install.sh`, never by hand-editing settings; it also flags a missing `jq` (the guard hooks fail open without it).

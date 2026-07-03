---
name: toolkit-maintenance
description: Change the agent-toolkit itself — add or revise a skill, hook, cap, core.md rule, or the installer/statusline — and land it so every machine picks it up. Use when codifying a session learning ("add this to the toolkit", "remember this globally", "make this a rule/skill everywhere"), when editing anything in the agent-toolkit repo (core.md, skills/, hooks/, install.sh), or when the SessionStart doctor reports the toolkit broken.
---

# Toolkit maintenance

The toolkit is a repo with the same discipline as production code — edit → verify → review → gated commit/push — because its consumers are every future session on every machine. Device config reaches it only through the `~/.claude/agent-toolkit` symlink; `readlink` that for the real checkout.

## Where a change lands (first decision, in order)

- **Always-true principle, every task** → `core.md` — a sentence, not a section; it loads every session, so it must stay small.
- **Task procedure or growing reference** → a skill (`skill-authoring` owns the craft and the cap-placement rule).
- **A cap's identity or boundary** → that cap's soul file (`skills/caps/`).
- **Mechanical enforcement** — must hold even if the model forgets → a hook under `hooks/` **plus a case in `tests/run.sh`**.
- **Wiring** — what `settings.json` points at → `install.sh` only; never hand-edit `~/.claude/settings.json` for toolkit-managed entries.
- **Device-local only** → not the toolkit's business; `~/.claude/CLAUDE.md` stays a one-line pointer.

One home: never duplicate a rule across these layers — link to where it lives.

## Verify before landing

- **Skill added/renamed:** sync into `~/.claude/skills` is automatic (SessionStart + on-skill-edit hooks) — confirm with `ls -l ~/.claude/skills/<name>`; tune the trigger description with `/skill-creator` eval when firing accuracy matters.
- **Hook changed:** extend `tests/run.sh` with the new case and run it — all green before commit. For the statusline, pipe a sample status JSON through `hooks/statusline.py`.
- **Wiring changed:** `./install.sh --dry-run` to preview the exact device-config diff, then `./install.sh` with the user's approval (it writes `~/.claude`).
- **Anything renamed/removed:** grep the whole repo for the retired name (core.md's sweep-on-rename) — README and `caps`' cross-cutting list are the usual stragglers.

## Land and propagate

- Commit in the toolkit repo under the standing gates (per-action approval, message verbatim + diff summary, no AI attribution) — then remind the user to approve a **push**: other machines only receive the change after it's on origin.
- On another machine, `git pull` in the checkout is the whole upgrade — the next SessionStart re-links skills and re-checks wiring automatically; a brand-new machine is one `git clone` + `./install.sh`.
- The SessionStart doctor prints `agent-toolkit doctor: ✗ …` into session context when something's broken — fix via `./install.sh`, never by hand-editing settings; it also flags a missing `jq` (the guard hooks fail open without it).

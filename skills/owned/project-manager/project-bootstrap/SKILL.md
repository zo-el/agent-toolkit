---
name: project-bootstrap
description: Scaffold a new project with the user's standard development contract — agent instructions, spec board, workflow pointers. Use when starting a brand-new repo, or when the user asks to set up the workflow / documentation skeleton in an existing one.
---

# Project bootstrap

Write the thin, repo-visible contract into a new project. The workflow **procedures** live in the agent-toolkit skills — `orchestrating-subagents` maps the phases, agents, and skills — so the repo carries only pointers plus its own specifics. **One home per rule.**

## Files to create

```
CLAUDE.md                 # session disciplines + workflow pointer + @AGENTS.md import
AGENTS.md                 # project map: what the repo is, stack, build/format/test commands, structure facts
documentation/
  README.md               # the spec board: an aligned table of specs/<feature> → status, plus the repo's spec rules
  specs/                  # empty; features land here
```

## CLAUDE.md must state

- **The workflow pointer:** the moment a session turns to building/changing a feature, follow the agent-toolkit development flow — `orchestrating-subagents` maps the phases (spec → plan → develop), the agents, and their skills; enter at the phase the work needs — detected from conversation, never prompted for.
- **For non-Claude agents/humans:** the core principles (`core.md`) and skills are plain markdown — include the toolkit clone command (`git clone git@github.com:zo-el/agent-toolkit.git`).
- **Approval gates:** local work — edits, builds, tests, commits, branches — is free; per-action approval for user/system config edits and destructive fs ops. **Publishing — any push, PR create/update, or public comment — is gated on showing the user the plan and getting an explicit go-ahead** (`core.md` § Publishing); never push or post on the user's behalf, and never add AI attribution to commits or PRs.
- **Documentation discipline:** no unsolicited `.md` files; spec/task deliverables are the carve-out.
- Any stack-specific session rules (e.g. "commands run inside `nix develop -c`" for flake repos).

## documentation/README.md (the spec space) must state

- The `specs/` directory **is the index** — a feature is in flight while its `tasks/` catalog exists, implemented once it's deleted; no status table to maintain (when work mirrors to a tracker, that is the live board).
- Where specs and tasks live (`specs/<feature>/` + `tasks/`), one line each on what they are.
- Any repo-specific spec rules (e.g. citation rooting conventions, cross-repo sync expectations for multi-repo projects).

## Procedure

1. Ask only what can't be inferred: project name, stack, test commands, single repo vs multi-repo.
2. Write the files, adapted to the answers — don't copy another project's specifics verbatim.
3. If the repo is brand-new, leave git initialization and the first commit to the user (per-action approval for commits always applies).

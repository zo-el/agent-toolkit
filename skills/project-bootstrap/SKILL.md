---
name: project-bootstrap
description: Scaffold a new project with the user's standard development contract — workflow docs, spec board, agent instructions. Use when starting a brand-new repo, or when the user asks to set up the workflow / documentation skeleton in an existing one.
---

# Project bootstrap

Write the thin, repo-visible contract into a new project so collaborators, CI, and other agents see the same rules the skills enforce. Keep every file thin; **one home per rule** — repo docs state the contract, the `feature-*` skills carry the live procedure.

## Files to create

```
CLAUDE.md                                # session disciplines + @AGENTS.md import
AGENTS.md                                # project map: what the repo is, stack, build/test commands, structure facts
documentation/
  DEVELOPMENT_WORKFLOW.md                # the 4-phase contract (outline below)
  SPEC_DISCIPLINE.md                     # Phase 1 detail (mirror the feature-spec skill, repo-visible)
  README.md                              # the spec board: an aligned table of specs/<feature> → status
  specs/                                 # empty; features land here
```

## CLAUDE.md must state

- The workflow trigger: the moment a session turns to building/changing a feature, the workflow starts at Phase 1 — detected from conversation, never prompted for.
- State-mutation approval: per-action approval for git commits/pushes/rebases, user/system config edits, and destructive fs ops; in-repo edits, builds, and tests allowed by default.
- Documentation discipline: no unsolicited `.md` files; spec/milestone deliverables are the carve-out; markdown per the `doc-style` skill (one paragraph = one line, aligned tables).
- Any stack-specific session rules (e.g. "commands run inside `nix develop -c`" for flake repos).

## DEVELOPMENT_WORKFLOW.md outline

- **Phase 1 — Spec:** feature folder under `documentation/specs/<feature>/`; decisions-only component docs; no status; speccing touches only specs. Detail in `SPEC_DISCIPLINE.md`.
- **Phase 2 — Planning:** `milestones/` catalog; self-contained milestones numbered by build order; outcome ACs (testable, 3–7, edge cases, no implementation detail); implementation as real-code diff blocks; test plan mapped to ACs.
- **Phase 3 — Development:** 3a implement (+unit tests) → 3b test (every available check) → 3c review (`/code-review`, triage, loop until clean).
- **Phase 4 — Finalize:** final review vs AC, changelog, branch + PR per repo with AC as body, post-merge spec sync, delete the shipped milestone. Phases 3–4 are the uniform Definition of Done; milestones never restate it.

## Procedure

1. Ask only what can't be inferred: project name, stack, test commands, single repo vs multi-repo.
2. Write the files, adapted to the answers — don't copy another project's specifics verbatim.
3. If the repo is brand-new, leave git initialization and the first commit to the user (per-action approval for commits always applies).

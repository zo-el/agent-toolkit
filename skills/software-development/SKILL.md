---
name: software-development
description: The end-to-end development workflow — spec → plan → develop → finalize. Fires the moment a session turns to building or changing a feature (new functionality described, a feature/fix handed over, a change scoped). Owns the phase sequence and gates; never jump to code — detect the entry phase from the conversation.
---

# Software development workflow

Every feature moves through four phases. Each phase's full procedure is its own skill — this skill owns the **sequence, the gates, and the transitions**. The user never has to name the workflow or a phase; detect it.

## The flow

| Phase        | Skill                | Produces                                      | Gate to the next phase                                                 |
| ------------ | -------------------- | --------------------------------------------- | ---------------------------------------------------------------------- |
| 1 — Spec     | `feature-spec`       | `documentation/specs/<feature>/` docs         | user review (`plannotator-loop`) until a round returns clean           |
| 2 — Plan     | `feature-milestones` | `milestones/NN-*.md`                          | AC-stub catalog approved; each deep plan reviewed → user flips `ready` |
| 3 — Develop  | `develop`            | the milestone's code + tests, review-clean    | every AC met, all suites green                                         |
| 4 — Finalize | `develop` (Ship)     | PRs, changelogs, spec sync, milestone deleted | merged                                                                 |

The `develop` skill is **not** feature-only — it's the universal build → test → review → ship discipline (a chore's code, a backlog fix, any standalone change use it too). Here it serves as Phases 3–4, adding the feature-specific extras (AC check, spec sync, milestone completion).

## Flow rules

- **Enter at the phase the work actually needs:** a new or revised contract → Phase 1; an approved spec → Phase 2; a `ready` milestone → Phase 3. Never code ahead of the phase the artifacts support.
- **Milestones move through 3–4 one at a time**; after one ships, return to the catalog for the next (or to Phase 1/2 if the spec moved).
- **Phase boundaries are user gates** — review rounds on specs and plans, explicit status flips on milestones, per-action approval on commits. Don't cross one silently.
- **Cross-cutting, always:** `plannotator-loop` for any substantial artifact review (the `core.md` principles already apply to every step).
- **Workflow artifacts follow the core *one home* rule:** specs are permanent (siblings may link to them), milestones and backlog items are temporary (self-contained — state what you need in your own words, never a pointer to them). Its test here: *finishing or changing one file must never force an edit to another* — if it does, the other file was tracking work it doesn't own, so fix the coupling, not the reference. A **completed milestone is frozen** — never edited again, so it holds no pointer to live or other work.
- **Repo specifics come from the project, not from these skills:** where specs live, build/test commands, shipping choreography — read the project's `CLAUDE.md` / `AGENTS.md`. If a project lacks the contract entirely, scaffold it with `project-bootstrap`.

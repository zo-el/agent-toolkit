---
name: implement
description: The end-to-end development workflow — spec → plan → develop → finalize. Fires the moment a session turns to building or changing ANY code — a feature, a fix, a chore, or a backlog item, not just new functionality — including when the user types /implement or says "implement", "work on", "develop", "execute", "build", or "ship". Owns the phase sequence and gates; scale the phases to the change but never the gates; never jump to code — detect the entry phase from the conversation.
---

# Implement — the development workflow

Every change runs through this workflow — a feature through all four phases; a fix, chore, or backlog item enters at the phase it needs (usually straight to Develop). Each phase's full procedure is its own skill — this skill owns the **sequence, the gates, and the transitions**. The user never has to name the workflow or a phase; detect it, or run it explicitly with `/implement`.

## The flow

| Phase        | Skill                | Produces                                      | Gate to the next phase                                                 |
| ------------ | -------------------- | --------------------------------------------- | ---------------------------------------------------------------------- |
| 1 — Spec     | `feature-spec`       | `documentation/specs/<feature>/` docs         | user review (`plannotator-loop`) until a round returns clean           |
| 2 — Plan     | `feature-tasks` | `tasks/NN-*.md`                          | AC-stub catalog approved; each deep plan reviewed → user flips `ready` |
| 3 — Develop  | `develop`            | the task's code + tests, review-clean    | every AC met, all suites green                                         |
| 4 — Finalize | `develop` (Ship)     | PRs, changelogs, spec sync, task deleted | merged                                                                 |

The `develop` skill is **not** feature-only — it's the universal build → test → review → ship discipline (a chore's code, a backlog fix, any standalone change use it too). Here it serves as Phases 3–4, adding the feature-specific extras (AC check, spec sync, task completion).

## Flow rules

- **Scale the phases, never the gates.** A small change may skip Phases 1–2 and enter at Develop — but the `develop` gates hold at *every* size: fmt / lint / typecheck / tests, an **actual `/code-review` invocation** (never merely offered, never a hand-rolled substitute), and the finalize Definition of Done (changelog, published-crate check, backlog sweep, PR). "It's only N lines" never justifies skipping a gate; if one feels disproportionate, run it anyway and say why.
- **Enter at the phase the work actually needs:** a new or revised contract → Phase 1; an approved spec → Phase 2; a `ready` task → Phase 3. Never code ahead of the phase the artifacts support.
- **Tasks move through 3–4 one at a time**; after one ships, return to the catalog for the next (or to Phase 1/2 if the spec moved).
- **Phase boundaries are user gates** — review rounds on specs and plans, explicit status flips on tasks, per-action approval on commits. Don't cross one silently.
- **Cross-cutting, always:** `plannotator-loop` for any substantial artifact review (the `core.md` principles already apply to every step).
- **Workflow artifacts follow the core *one home* rule:** specs are permanent (siblings may link to them), tasks and backlog items are temporary (self-contained — state what you need in your own words, never a pointer to them). Its test here: *finishing or changing one file must never force an edit to another* — if it does, the other file was tracking work it doesn't own, so fix the coupling, not the reference. A **completed task is frozen** — never edited again, so it holds no pointer to live or other work.
- **Repo specifics come from the project, not from these skills:** where specs live, build/test commands, shipping choreography — read the project's `CLAUDE.md` / `AGENTS.md`. If a project lacks the contract entirely, scaffold it with `project-bootstrap`.

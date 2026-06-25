---
name: linear-sync
description: Mirror the project's tracked work (a feature's tasks) into a Linear board for team visibility and collaboration. Use when planning or finalizing a feature's tasks, when the user says sync / push / track / update Linear (or "add to the board"), at a develop build-start or finalize gate, or to look up which Linear issue maps to a local task doc (and back).
---

# Linear sync

Mirror the repo's tracked work into Linear so others can view, track, and shape it. The **repo is the source of truth for the plan**; Linear **owns each task's acceptance criteria** once planned (others suggest, you review). Write titles + AC for a non-technical reader, faithful to the source (per `documentation-style`).

## The shape

| Repo | Linear |
| --- | --- |
| **feature** (a spec) | a **label** — spans the feature's whole life, across re-plans |
| **round** — the planned set of tasks from the current spec | a **milestone**, named `<Feature>: <goal in 1–3 words>` (or `<Feature>: base` for the first / broad round; `v2`+ for later broad ones) |
| **task** (one `specs/<feature>/tasks/NN-*.md`) | an **issue** under that milestone, carrying the label |
| the round as one ticket | a **parent issue** `<Feature>: <round>` whose **sub-issues** are the round's task-issues (the "one big ticket, tasks inside" board view) |

A round can fan across projects: each task-issue sits in **the project that owns that work**, the parent sits in the primary one (cross-project sub-issues are fine), and the label ties it all together.

## Per-workspace opt-in — always resolve first

Before any Linear write, resolve **this project's Linear binding** — a `## Linear mirror` section in the project's `AGENTS.md` / `CLAUDE.md`. If none exists, **ask once** ("wire this workspace to Linear?") and record the answer: **yes** → write the binding; **no** → record an explicit opt-out so it never asks again. Opted-out or declined → skip Linear silently. The binding holds every repo-specific value (team id, project map, state / label / priority names); **never hard-code those here** — a clone or a different project decides for itself.

## Lifecycle

1. **Plan a round locally** — `specs/<feature>/tasks/` holds the round's tasks, each with draft AC.
2. **At `ready`** — create the round's **milestone** + its **parent issue**; create each task as an **issue** (with its AC) and make it a **sub-issue** of the parent; then **strip the AC from the task doc** (Linear is now its authority; the doc keeps plan + tests + context + the `**Linear:**` link).
3. **While implementing** — re-read the issue's AC + comments when you pick a task up and again before closing it; fold any change others made into the plan with the user **before** it's done.
4. **On done** — move the issue to Done and **paste the as-built plan as a comment**.
5. **Spec re-plan → a new round** — a re-plan that yields a *new set of tasks* gets a **new milestone + parent**, holding the new/incomplete tasks; already-completed tasks stay in their old round. The **label** spans all rounds; locally the `tasks/` dir is regenerated for the new round.

## Mapping — ownership, not duplication

- Each task → an issue in **the project that owns that work**; **shared machinery many services merely *use* lives once**, in the project that owns it — never a task per consumer.
- **Area → the binding's existing labels**; **type → Feature / Bug / Improvement**; **weight → the team's estimate**, by scope; **priority only for the high ones**; **cycle** by the cycle rule below; **assignee** left to the user.
- **Status** (binding's state names): planned → Backlog/Ready · building → In Progress · in review → In-Review/Test · shipped → Done · dropped → Canceled.

## Cycles — the cycle is each task's *planned* week

When the team runs cycles, set every issue's cycle to the **week it's planned to land**, so the cycles read as the round's roadmap — never use the current cycle as a catch-all for already-done or in-flight work.

- Lay the round's tasks out in **build order** (prerequisites first) and **spread them across the cycles** from the round's start to the cycle containing the milestone's `targetDate`, balanced by **estimate** (roughly even points per cycle — a small round may be one task a cycle, a fast multi-dev one several). The last task lands in the deadline cycle; if even that won't hold the spread, **flag over-commitment** rather than cramming past it. (Don't pin a fixed per-cycle budget — the deadline + the round's size set the pace.)
- Apply this to **every** task regardless of status: a **completed** task sits in its planned cycle and simply reads as *done early* if it beat its slot; an **in-flight** task sits in its planned cycle too. Don't relocate done/started work into the current sprint.
- Sets the **cycle** only; assignee + priority stay the user's. Resolve cycle dates via `list_cycles` against the milestone's `targetDate`; a re-sync re-runs this for the whole round.

## The link — glanceable both ways, and the dedup key

- **Local → Linear:** a `**Linear:** <ISSUE-ID>` line in the task doc header.
- **Linear → local:** a `Spec: <feature>/<task-slug>` line at the foot of the issue description.
- **Search by the `Spec:` ref before creating**, so a re-sync updates the issue instead of duplicating it; write the issue id back into the doc on create. (Backfilling an already-completed feature: still move the AC to Linear and strip the doc to an AC→Linear pointer — one consistent model everywhere.)

## Discipline

- **Local task first — never Linear-first.** Every Linear issue mirrors a task that already exists locally (`specs/<feature>/tasks/NN-*.md`, or the round's parent). **Never create or update a Linear issue without its local task existing first** — the repo is the plan's source of truth, so a Linear-only issue is invisible to anyone reading the local copies and gets lost. About to write to Linear with no local home? Stop, create the local task, then mirror.
- **Outward-facing — approve before writing.** At each gate show the planned create/update (title, milestone, parent, status, labels, weight) and get an OK. Reads are free.
- **Gates:** a round reaches `ready` → create milestone + parent + task-issues · build-start → pull AC + comments and reconcile · status flips → update · `develop` Ship → move to Done + paste the as-built plan as a comment.
- **MCP gotchas:** `save_milestone` rename only applies when a `description` is passed in the same call; a large parallel `save_issue` batch can silently drop its first calls — verify each result's `updatedAt` / `parentId` and retry any that didn't take.

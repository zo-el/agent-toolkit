---
name: linear-sync
description: Keep the Linear board true to the project, both directions — mirror the task catalog out to the board, and audit it back against reality (merged PRs + local statuses vs each issue, show the diff, apply on approval). Use when planning or finalizing tasks, when the user says sync / push / track / update Linear or "add to the board", when asked what's out of sync / to check or update statuses / to reconcile after work merged, at a develop build-start or finalize gate, or to look up which Linear issue maps to a local task doc (and back).
---

# Linear sync

Mirror the repo's tracked work into Linear so others can view, track, and shape it. The **repo is the source of truth for the plan**; Linear **owns each task's acceptance criteria** once the task is `ready` (others suggest, you review). Write titles + AC for a non-technical reader, faithful to the source (per `documentation-style`).

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
2. **At `ready`** — create the round's **milestone** + its **parent issue**; create each task as an **issue** (with its AC) and make it a **sub-issue** of the parent; then **strip the AC from the task doc** (Linear is now its authority; the doc keeps context + the `**Linear:**` link, and gains the Developer's plan + test plan at pick-up).
3. **While implementing** — re-read the issue's AC + comments when you pick a task up and again before closing it; fold any change others made into the plan with the user **before** it's done.
4. **On done** — move the issue to Done and **paste the as-built plan as a comment**.
5. **Spec re-plan → a new round** — a re-plan that yields a *new set of tasks* gets a **new milestone + parent**, holding the new/incomplete tasks; already-completed tasks stay in their old round. The **label** spans all rounds; locally the `tasks/` dir is regenerated for the new round.
6. **Feature ships (last task Done)** — delete the local `tasks/` set, flip the round's parent issue Done, and check the milestone's remaining scope + target date.

## Board audit — reconcile the board to reality

The reverse of mirroring out: read what actually happened and true the board up, using the write mechanics in this same skill (the preview-diff Discipline, the as-built comment, the state map, cycles, the gotchas). Run it whenever the `project-manager` agent starts, whenever asked what's out of sync / to check or update statuses / to reconcile after work merged, and before `next-up`.

1. **Freshness first** — probe both remotes and sync the clone; a stale or diverged clone reports phantom drift (the clone-freshness gate below). If reconciling is blocked, audit only what merged-PR evidence supports, and say so.
2. **Gather the three sides** — local (`specs/<feature>/tasks/*` `Status`, `chores/C*` existence, backlog count) · GitHub (PRs merged since the last audit **and** all open, across the owned repos) · Linear (issues by active label / recently updated, with status + parent). Fan the gather to parallel read-only agents when the surface is large (`orchestrating-subagents`).
3. **Compare per task, evidence-driven** — merged PR → **Done** + the as-built comment (the merge is the trigger, never the local commit); open PR → **In-Review** (attach it); a local doc lagging a flip → fix the local doc; a round **parent** → Done only once its last child closes, then check the milestone's scope + date; a shipped feature/chore → delete the `tasks/` set or chore doc per its ship rule; merged work with **no issue** → flag for a retro-ticket, never silently absorb.
4. **Show the diff, then apply** — the grouped preview (Discipline below), get the OK, then the flips + comments + deletions + the umbrella commit (push is the user's gate). Hand the true board to `next-up`.

## Mapping — ownership, not duplication

- Each task → an issue in **the project that owns that work**; **shared machinery many services merely *use* lives once**, in the project that owns it — never a task per consumer.
- **No milestone-less issues.** Every issue lands in a milestone: feature work in its round milestone; miscellaneous / bug work in the project's standing **`Misc & bugs`** catch-all, target-dated **two weeks before the project's target date** (create it on first need; sweep strays into it when found). An issue with no project first needs a project decision.
- **Area → the binding's existing labels**; **type → Feature / Bug / Improvement**; **weight → the team's estimate**, by scope; **priority only for the high ones**; **cycle** by the cycle rule below; **assignee** left to the user.
- **Status** (binding's state names) — **decided work defaults to `Ready`, not Backlog.** A created, scoped task we intend to do → **Ready**, even if it hasn't started, is blocked, or is a later phase (Ready means "decided, not yet in progress" — not "being worked now"). **`Backlog` is only for the undecided** — a rough placeholder or stub whose scope isn't settled, or a maybe that hasn't been committed to. Then: building → **In Progress** · in review → **In-Review/Test** · shipped → **Done** · dropped → **Canceled**.

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

- **Milestones are user structure — never create one unilaterally.** Default to filing new work into the existing milestone that owns the workstream; a new milestone (or a rename) happens only on the user's explicit say-so, with the name + project shown first. A round *maps* to a milestone — it doesn't automatically *mint* one (the "create milestone" gate below runs through this rule).
- **IDs never travel alone.** In anything user-facing — previews, reports, questions — pair every issue/task ID with its title (`UNYT-901 "Deploy v0.93 and open the migration window"`); a bare number forces the user to go look it up before they can answer.
- **Clone freshness first.** Before a sync, check the local clone against its remote tip (`gh api repos/<owner>/<repo>/commits?sha=<base>` works when `git fetch` doesn't): a stale or diverged clone's docs aren't truth — statuses lag, and locally-filed IDs collide with items filed from other machines. Reconcile first; if reconciling is blocked, sync only what merged-PR evidence supports and say so.
- **Local task first — never Linear-first.** Every Linear issue mirrors a task that already exists locally (`specs/<feature>/tasks/NN-*.md`, or the round's parent). **Never create or update a Linear issue without its local task existing first** — the repo is the plan's source of truth, so a Linear-only issue is invisible to anyone reading the local copies and gets lost. About to write to Linear with no local home? Stop, create the local task, then mirror.
- **Outward-facing — approve before writing, and the approval must reach the *user*.** Running as the `project-manager` agent your transcript is never read, so a preview you print to yourself approves nothing: return the diff and let the orchestrator put it in front of the user (`agents/project-manager.md`), and expect the `guard-linear` hook to prompt on each write as the backstop. At each gate present every planned write grouped **Project → Milestone**, one row per task, and **name the Linear project + milestone each issue lives in** (a column, or the group header — never omit it; the user reads the board by where things live). Each row is `local task ↔ issue` with every changing field as a labeled source→target diff (`Linear: <current> → <new>`, alongside what the local doc says; creates marked `new`); then get an OK. A bare unlabeled "now" hides which side it describes. Reads are free.
- **Gates:** a round reaches `ready` → create milestone + parent + task-issues · build-start → pull AC + comments and reconcile · status flips → update · `develop` Ship → move to Done + paste the as-built plan as a comment.
- **MCP gotchas:** `save_milestone` rename only applies when a `description` is passed in the same call; a large parallel `save_issue` batch can silently drop its first calls — verify each result's `updatedAt` / `parentId` and retry any that didn't take; setting a started/completed state auto-adds the current cycle — if the issue shouldn't sit in the cycle, null `cycle` in a separate follow-up call (a combined state+cycle:null call loses to the auto-add).

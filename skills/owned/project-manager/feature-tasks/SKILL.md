---
name: feature-tasks
description: Phase 2 of the development workflow — break a finished spec into tasks. Use when a spec is ready to plan, when re-planning after a spec change, or when the user asks for tasks or acceptance criteria.
---

# Feature tasks (Phase 2)

Planning breaks the spec into ordered, self-contained tasks in `documentation/specs/<feature>/tasks/NN-<name>.md`.

## The catalog

- The `tasks/` directory **is** the catalog: the Status line separates open from completed; no separate index to sync. A completed task stays as a historical reference (`Status: completed` — as-built truth lives in the spec docs) until the feature ships, and is **frozen the moment it completes** — never edited again, so it carries no pointer to live or other work; the set is deleted together once every task is implemented.
- Numbered by build order; reorder/renumber/remove freely while open (use plain `mv`, never commit without approval).
- **Self-contained, both directions:** nothing points at a task (not specs, not code, not siblings), **and** a task points at no other file for its work or status — no "open work in B<NN>", no "see task 03". Need something an earlier task produces, or to record follow-up / out-of-scope work? State it as a **precondition or note in your own words**, never a pointer to another file.
- One coherent outcome per task; parallel work stays inside one task as sections under a single AC set.
- **Don't pre-split by instance or round:** one task holds the plan (per-instance deltas as sections) until execution genuinely needs breaking out.

## Build before deploy

Order tasks **build-first, deploy-together**: build tasks land and are reviewed without touching the live system; the live cutover is **one release task** (the release/deploy track owns it), gated on the build tasks. Two carve-outs: a deployment that does **not** affect the live system and only stands a tool up can land **independently**; a **test/staging deploy** may precede the official one as its own task. Keep live/infra-cutover acceptance criteria in the release task, never in the build tasks.

## Build, then the testing phase

A round's catalog is build tasks **plus a testing phase**: after the build tasks, plan the **automated e2e + manual test pass** that proves the round's outcomes together — one task (or a small set) with AC like any other, covering the end-to-end flows and the user-facing checks. Build tasks still carry their own tests (the `develop` gate); the testing phase is the round-level proof, and it precedes any release/deploy task (**build → test → release**). What it surfaces is decided in the round — fixed, tasked, or explicitly accepted — per the `backlog` skill's active-work rule.

## Two-stage planning

1. **Catalog pass** — for the whole feature, create AC-only stubs (Title, Status, AC, 2–3 line context) so the user reviews the breakdown before any deep planning.
2. **Deep-plan one task at a time** on request — fill Implementation + Test plan, then review via the `plannotator-loop` skill before marking it ready.

## Acceptance criteria — outcomes, not work

- Each criterion is a clear, **testable pass/fail statement of expected behavior** (checklist or Given/When/Then), standing alone, free of implementation detail — the *how* belongs in Implementation.
- Cover **error and edge states**, not just the happy path (rejections, timeouts, retries, misconfiguration).
- 3–7 per task; more usually means it should split.
- **If the project mirrors to Linear** (`linear-sync`): at `ready` the AC moves to the task's Linear issue and is **stripped from the doc** — Linear becomes its sole authority (others suggest, you review); the doc then keeps plan + tests + context + the `**Linear:**` link.

## Task shape

- **Title** — one line: what reaching it achieves.
- **Status** — one line (`stub` → `AC suggested` → `ready for review` → `ready` → `in development`).
- **Acceptance criteria** — at the top (see above).
- **Summary / context** — what it does, what already exists and survives, why it's needed, preconditions, target repo(s).
- **Implementation** — ordered steps naming real files. **Ground every step in the actual code first** (read the files, map the full change/rename surface with grep before writing). Show changes as real code — diffs for reshapes, faithful sketches for new code, never pseudo-prose (formatting per `documentation-style`).
- **Test plan** — each test tier mapped to the AC it proves. **Reuse expensive integration scenarios**: fold new cases into existing scenarios as sub-cases along their timeline; spin up a new scenario only when genuinely unavoidable.
- **Anything else** — open questions, out-of-scope notes, known interim gaps (e.g. "the UI breaks against real backends until its own task lands — accepted because …").

## Definition of Done

DoD is uniform and owned by the `develop` skill's Ship step (tests green, review clean, changelog, spec sync, task deletion) — tasks state only their own AC and never restate it.

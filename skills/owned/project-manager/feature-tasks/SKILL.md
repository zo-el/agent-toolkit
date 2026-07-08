---
name: feature-tasks
description: The Plan phase of the development flow — verify the spec's suggested breakdown into a task catalog with acceptance criteria. Use when a spec is ready to plan, when re-planning after a spec change, or when the user asks for tasks or acceptance criteria.
---

# Feature tasks (the Plan phase)

Planning turns the spec — and the architect's **Suggested breakdown** in it — into ordered, self-contained tasks in `documentation/specs/<feature>/tasks/NN-<name>.md`. The PM decides the decomposition and owns each task's **AC, scope, and order**; the **detailed plan is the Developer's**, written at pick-up (`develop` § Build).

## The catalog

- The `tasks/` directory **is** the catalog: the Status line separates open from completed; no separate index to sync. A completed task stays as a historical reference (`Status: completed` — as-built truth lives in the spec docs) until the feature ships, and is **frozen the moment it completes** — never edited again, so it carries no pointer to live or other work; the set is deleted together once every task is implemented.
- Numbered by build order; reorder/renumber/remove freely while open (use plain `mv`).
- **Self-contained, both directions:** nothing points at a task (not specs, not code, not siblings), **and** a task points at no other file for its work or status — no "open work in B<NN>", no "see task 03". Need something an earlier task produces, or to record follow-up / out-of-scope work? State it as a **precondition or note in your own words**, never a pointer to another file.
- One coherent outcome per task; parallel work stays inside one task as sections under a single AC set.
- **Scope and name a task by component.** A task is one component's slice — the DNA, the UI, a named service, `automation` — and its filename and title lead with that component (`dna-close-time-notarisation`, `ui-two-channel-update-surface`, `migration-service-skip-routing`). Work spanning components splits along them, and a component's whole slice groups into one task rather than splitting by sub-feature, so progress reads component by component; split further only when the AC count forces it. The test and deploy phases are the exception — named by type (`…-test-plan`, `…-deployment`), they encapsulate an intention no single component owns.
- **Don't pre-split by instance or round:** one task holds the plan (per-instance deltas as sections) until execution genuinely needs breaking out.

## Build before deploy

Order tasks **build-first, deploy-together**: build tasks land and are reviewed without touching the live system; the live cutover is **one release task** (the release/deploy track owns it), gated on the build tasks. Two carve-outs: a deployment that does **not** affect the live system and only stands a tool up can land **independently**; a **test/staging deploy** may precede the official one as its own task. Keep live/infra-cutover acceptance criteria in the release task, never in the build tasks.

## Build, then the testing phase

A round's catalog is build tasks **plus a testing phase**: after the build tasks, plan the **automated e2e + manual test pass** that proves the round's outcomes together — one task (or a small set) with AC like any other, covering the end-to-end flows and the user-facing checks. Build tasks still carry their own tests (the `develop` gate); the testing phase is the round-level proof, and it precedes any release/deploy task (**build → test → release**). What it surfaces is decided in the round — fixed, tasked, or explicitly accepted — per the `backlog` skill's active-work rule.

## The catalog pass

From the spec's **Suggested breakdown**, decide the actual units — merge, split, resequence, drop: the suggestion is input, the catalog is the decision. Write each unit as an AC-stub (Title, Status, AC, 2–3-line context), review the catalog with the user (`plannotator-loop`), and **remove the consumed Suggested-breakdown section from the spec README in the same pass** — the catalog supersedes it. The user flips tasks `ready`; the Developer writes each task's detailed plan at pick-up and flips it `planned` once the plan reviews clean (`develop` § Build).

## Acceptance criteria — outcomes, not work

- Each criterion is a clear, **testable pass/fail statement of expected behavior** (checklist or Given/When/Then), standing alone, free of implementation detail — the *how* belongs in Implementation.
- Cover **error and edge states**, not just the happy path (rejections, timeouts, retries, misconfiguration).
- 3–7 per task; more usually means it should split.
- **If the project mirrors to Linear** (`linear-sync`): at `ready` the AC moves to the task's Linear issue and is **stripped from the doc** — Linear becomes its sole authority (others suggest, you review); the doc then keeps context + the `**Linear:**` link, and gains the Developer's plan + test plan at pick-up.

## Task shape

- **Title** — one line: what reaching it achieves.
- **Status** — one line (`stub` → `AC suggested` → `ready for review` → `ready` → `planned` → `in development`).
- **Acceptance criteria** — at the top (see above).
- **Summary / context** — what it does, what already exists and survives, why it's needed, preconditions, target repo(s).
- **Implementation** — left empty at planning; **the Developer fills it at pick-up** (`develop` § Build).
- **Test plan** — likewise the Developer's, at pick-up.
- **Anything else** — open questions, out-of-scope notes, known interim gaps (e.g. "the UI breaks against real backends until its own task lands — accepted because …").

## Definition of Done

DoD is uniform and owned by the `develop` skill's Ship step (tests green, review clean, changelog, spec sync, the task's completion flip) — tasks state only their own AC and never restate it.

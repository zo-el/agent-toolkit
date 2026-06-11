---
name: feature-milestones
description: Phase 2 of the development workflow — break a finished spec into milestones. Use when a spec is ready to plan, when re-planning after a spec change, or when the user asks for milestones or acceptance criteria.
---

# Feature milestones (Phase 2)

Planning breaks the spec into ordered, self-contained milestones in `documentation/specs/<feature>/milestones/NN-<name>.md`.

## The catalog

- The `milestones/` directory **is** the catalog: the files present are the open milestones; no separate index to sync; a milestone is deleted once it ships (its as-built lives on in the spec docs).
- Numbered by build order; reorder/renumber/remove freely while open (use plain `mv`, never commit without approval).
- **Self-contained:** nothing points at a milestone — not specs, not code, not siblings. Need something an earlier milestone produces? State it as a **precondition in your own words**.
- One coherent outcome per milestone; parallel work stays inside one milestone as sections under a single AC set.

## Two-stage planning

1. **Catalog pass** — for the whole feature, create AC-only stubs (Title, Status, AC, 2–3 line context) so the user reviews the breakdown before any deep planning.
2. **Deep-plan one milestone at a time** on request — fill Implementation + Test plan, then review via the `plannotator-loop` skill before marking it ready.

## Acceptance criteria — outcomes, not work

- Each criterion is a clear, **testable pass/fail statement of expected behavior** (checklist or Given/When/Then), standing alone, free of implementation detail — the *how* belongs in Implementation.
- Cover **error and edge states**, not just the happy path (rejections, timeouts, retries, misconfiguration).
- 3–7 per milestone; more usually means it should split.

## Milestone shape

- **Title** — one line: what reaching it achieves.
- **Status** — one line (`stub` → `AC suggested` → `ready for review` → `ready` → `in development`).
- **Acceptance criteria** — at the top (see above).
- **Summary / context** — what it does, what already exists and survives, why it's needed, preconditions, target repo(s).
- **Implementation** — ordered steps naming real files. **Ground every step in the actual code first** (read the files, map the full change/rename surface with grep before writing). Code-shaped changes in fenced blocks that read like real code: reshapes as ```diff (every added/removed field or function explicit, unchanged lines kept for context), brand-new code as faithful ```rust/```ts sketches — never pseudo-prose.
- **Test plan** — each test tier mapped to the AC it proves. **Reuse expensive integration scenarios**: fold new cases into existing scenarios as sub-cases along their timeline; spin up a new scenario only when genuinely unavoidable.
- **Anything else** — open questions, out-of-scope notes, known interim gaps (e.g. "the UI breaks against real backends until its own milestone lands — accepted because …").

## Definition of Done

DoD is uniform and owned by the development workflow (Phase 3–4: tests green, review clean, changelog, spec sync, milestone deletion) — milestones state only their own AC and never restate it.

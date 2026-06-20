---
name: feature-milestones
description: Phase 2 of the development workflow — break a finished spec into milestones. Use when a spec is ready to plan, when re-planning after a spec change, or when the user asks for milestones or acceptance criteria.
---

# Feature milestones (Phase 2)

Planning breaks the spec into ordered, self-contained milestones in `documentation/specs/<feature>/milestones/NN-<name>.md`.

## The catalog

- The `milestones/` directory **is** the catalog: the Status line separates open from completed; no separate index to sync. A completed milestone stays as a historical reference (`Status: completed` — as-built truth lives in the spec docs) until the feature ships, and is **frozen the moment it completes** — never edited again, so it carries no pointer to live or other work; the set is deleted together once every milestone is implemented.
- Numbered by build order; reorder/renumber/remove freely while open (use plain `mv`, never commit without approval).
- **Self-contained, both directions:** nothing points at a milestone (not specs, not code, not siblings), **and** a milestone points at no other file for its work or status — no "open work in B<NN>", no "see milestone 03". Need something an earlier milestone produces, or to record follow-up / out-of-scope work? State it as a **precondition or note in your own words**, never a pointer to another file.
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
- **Implementation** — ordered steps naming real files. **Ground every step in the actual code first** (read the files, map the full change/rename surface with grep before writing). Show changes as real code — diffs for reshapes, faithful sketches for new code, never pseudo-prose (formatting per `documentation-style`).
- **Test plan** — each test tier mapped to the AC it proves. **Reuse expensive integration scenarios**: fold new cases into existing scenarios as sub-cases along their timeline; spin up a new scenario only when genuinely unavoidable.
- **Anything else** — open questions, out-of-scope notes, known interim gaps (e.g. "the UI breaks against real backends until its own milestone lands — accepted because …").

## Definition of Done

DoD is uniform and owned by the `develop` skill's Ship step (tests green, review clean, changelog, spec sync, milestone deletion) — milestones state only their own AC and never restate it.

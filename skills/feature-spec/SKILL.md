---
name: feature-spec
description: Phase 1 of the development workflow — write or revise a feature spec. Use the moment a session turns to new functionality, a scoped feature/fix is handed over, or the user asks to update specs — before any planning or code. Never wait to be asked for "the spec phase"; detect it from the conversation.
---

# Feature spec (Phase 1)

Define what the feature is before any code. The spec is the design contract every later phase builds against.

## A feature is a folder

```
documentation/specs/<feature>/
  README.md          # overview — what the feature is + a mermaid diagram of components and flows + links to each doc
  <component>.md     # one doc per component, named for it (dna.md, ui.md, <service>.md, …)
  milestones/        # created in Phase 2 (planning), never while speccing
```

`<feature>` is short, lowercase, hyphen-separated, stable once landed.

## Component doc rules

- State the **expected end-state** as standing truth — what the component is meant to do, the contract it exposes.
- **Decisions, not explanations** — short, clear decision points, not surrounding prose; no speculation, no option-shopping.
- **Code shapes get their own fenced block** — types, externs, payloads, endpoints as rough code (```rust / ```ts / ```json — the expected shape, not pasted implementation) followed by a one-line note of intent.
- **No status** — no `Status:` headers, no Implemented/Planned/Delta sections; milestones carry status.
- Cite existing code as `path:line` (with a `**Paths relative to:**` header line); don't paste it.
- Error/edge behavior is part of the contract: response variants, failure modes, and trust/threat notes are decisions too.

## Discipline

- **Speccing touches only the specs** — never update milestones, code, or other docs to match a revised spec; reconciling them is Phase 2 work.
- **Ripple every decision change through the whole spec folder in the same pass** — diagrams, error tables, naming, sibling docs. Grep the folder for stale terms before finishing (renamed functions, removed fields, dead error codes).
- **One home per rule** — a fact lives in exactly one doc; siblings link to it, never restate it.
- **Keep specs and code in sync** — when later code changes alter documented behavior, the matching spec doc updates in the same change.
- Review substantial spec work with the `plannotator-loop` skill; format everything per the `doc-style` skill.

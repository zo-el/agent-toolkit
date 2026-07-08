---
name: feature-spec
description: The Spec phase of the development flow — write or revise a feature spec, ending with a suggested task breakdown the Plan phase verifies. Use the moment a session turns to new functionality, a scoped feature/fix is handed over, or the user asks to update specs — before any planning or code. Never wait to be asked for "the spec phase"; detect it from the conversation.
---

# Feature spec (the Spec phase)

Define what the feature is before any code. The spec is the design contract every later phase builds against.

## A feature is a folder

```
documentation/specs/<feature>/
  README.md          # overview — what the feature is + a mermaid diagram of components and flows + links to each doc
  <component>.md     # one doc per component, named for it (dna.md, ui.md, <service>.md, …)
  tasks/        # created in the Plan phase (feature-tasks), never while speccing
```

`<feature>` is short, lowercase, hyphen-separated, stable once landed.

## Component doc rules

Prose and formatting follow the `documentation-style` skill; these are the spec-specific rules on top.

- State the **expected end-state** as standing truth — what the component is meant to do, the contract it exposes.
- **Code shapes are the expected shape, not the implementation** — types, externs, payloads, endpoints as rough code with a one-line note of intent; never paste real code.
- **No status, no tracking** — no `Status:` headers, no Implemented/Planned/Delta sections, and no execution history (PR numbers, merge dates, tracker IDs, "shipped" notes): the spec states what is; open todos live in `tasks/`, and the when/where/who lives in the tracker and git.
- Cite existing code as `path:line` (with a `**Paths relative to:**` header line); don't paste it.
- Error/edge behavior is part of the contract: response variants, failure modes, and trust/threat notes are decisions too.

## Discipline

- **End the spec with a `## Suggested breakdown` section in README.md** — the natural build units the design implies: a title + one-line outcome each, in rough dependency order. No AC, no implementation steps — it's decomposition *input* for the Plan phase, consumed and removed when the catalog lands (`feature-tasks` owns that pass).
- **Speccing touches only the specs** — never update tasks, code, or other docs to match a revised spec; reconciling them is Plan-phase work (`feature-tasks`).
- **Ripple every decision change through the whole spec folder in the same pass** — diagrams, error tables, naming, sibling docs. Grep the folder for stale terms before finishing (renamed functions, removed fields, dead error codes).
- **Keep specs and code in sync** — when later code changes alter documented behavior, the matching spec doc updates in the same change.
- Review substantial spec work with the `plannotator-loop` skill.

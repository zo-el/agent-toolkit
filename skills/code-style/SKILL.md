---
name: code-style
description: How to write code for this user — principles beyond what the formatter enforces (comments, naming, reuse, structure). The code parallel of doc-style. Use whenever writing or substantially editing source.
---

# Code style

How code should read, beyond what rustfmt / prettier enforce.

## Comments

- **Comments document how the code IS, never how it changed.** Write them only for non-obvious intent or trade-offs — never to narrate code, and never the edit history (`used to…`, `previously…`, `removed/renamed X`, `raised from…`, `now does…`, `deferred to…`). State current behaviour in the present tense, as if the code had always been this way.
- **What changed belongs in the changelog / commit message** — that is its only home. The diff records what changed; the comment records what *is*.
- When you touch a file, strip any change-narration you find in its comments (yours or pre-existing) — the same reflex as the stale sweep strips retired identifiers.

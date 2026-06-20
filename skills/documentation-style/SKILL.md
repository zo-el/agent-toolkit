---
name: documentation-style
description: How written output should read, by type — code comments, markdown, READMEs, changelogs, commit messages. Use whenever writing or editing any code comment, markdown file, doc, README, spec, changelog, or commit message; apply the section for the type you're writing. Beyond what rustfmt / prettier / linters enforce.
---

# Documentation style

How the written and documentary parts of the work should read, beyond what formatters enforce. Apply the section for whatever you're writing.

## Code comments

- **The code is the documentation — don't restate it.** If the code reads clearly, write no comment. Add one only for: a genuinely unusual approach, an **intentional** departure from the standard/recommended way (state why), or a name or value that isn't self-explanatory.
- **Comments document how the code IS, never how it changed.** Write them only for non-obvious intent or trade-offs — never to narrate code, and never the edit history (`used to…`, `previously…`, `removed/renamed X`, `raised from…`, `now does…`, `deferred to…`). State current behaviour in the present tense, as if the code had always been this way.
- **What changed belongs in the changelog / commit message** — that is its only home. The diff records what changed; the comment records what *is*.
- When you touch a file, strip any change-narration you find in its comments (yours or pre-existing).

## Markdown

Readable directly as **raw `.md`** — read in editors and terminals as often as rendered.

- **Decisions, not explanations** — short, to-the-point bullets that state what a thing *is* (its end-state / contract), not paragraphs of reasoning. Minimal why; no speculation or option-shopping.
- **One paragraph = one line of source** — no hard-wrapping body text; bullets, blockquotes, table rows, and code fences keep their own lines.
- **Tables: align the pipes** — pad every cell to its column's width; separator-row dashes span the column. Generate the alignment with a small script (don't hand-pad — it drifts) and verify all lines are equal length. Order rows by relevance (e.g. in-progress before done).
- **Anything code-shaped goes in its own fenced block** with the right language tag and a one-line note of what it's meant to do; changes to existing code as ```diff blocks with explicit +/- lines and unchanged context kept.
- **Status markers** — `[x]`/`[ ]` checkboxes, with a state emoji after an empty bracket when useful; emojis indicate state, never feelings; keep docs professional.
- **No unsolicited docs** — don't create `.md` files or expand docs unless asked; no breadcrumbs; the carve-out is workflow deliverables (specs, milestones).

### Table alignment helper

```python
def align(rows, indent=""):
    w = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    line = lambda r: indent + "| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |"
    return "\n".join([line(rows[0]), indent + "| " + " | ".join("-" * x for x in w) + " |", *map(line, rows[1:])])
```

## README

- **A README is a few lines, not a manual** — what the repo is (1–3 lines), how to run it, and how to test it (link the testing doc if one exists). Add license and badges if available.
- Nothing more: no feature tours, design rationale, or API dumps — those live in the code and specs. A section that grows belongs in a linked doc, not the README.

## Changelog

- **A changelog entry is a one-line bookmark** — a very short summary of the completed task, not a re-explanation of it. The code is the documentation and the spec is the contract; the changelog only points to *what* changed. No rationale, implementation detail, or restated diff — those live in the code, the commit, and the spec.
- **Expand only when it affects consumers** — a breaking or behaviour-changing release (e.g. a published crate's API) earns a short **warning + migration note** so downstream users know what to do. That is the one case where more than a line belongs.
- **Structure follows [Keep a Changelog](https://keepachangelog.com)** — entries under `## [Unreleased]`, grouped by Added / Changed / Deprecated / Removed / Fixed / Security.

## Commit messages

- **One short line** — a concise summary of the change in [Conventional Commits](https://www.conventionalcommits.org) form (`feat:` / `fix:` / `chore(scope):`). The diff is the detail.
- Add a body only when the change genuinely needs a why or a warning — the same bar as expanding a changelog entry (rare).

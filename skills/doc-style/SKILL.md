---
name: doc-style
description: How to write markdown for this user — applies to every doc (specs, milestones, READMEs, notes) in every project. Use whenever creating or substantially editing a markdown file.
---

# Doc style

Markdown must be readable directly as **raw `.md`** — it is read in editors and terminals as often as rendered.

## Rules

- **Decisions, not explanations** — rules/practices as short, to-the-point bullets, never prose paragraphs that bury the point.
- **One paragraph = one line of source** — no hard-wrapping body text; bullets, blockquotes, table rows, and code fences keep their own lines.
- **Tables: align the pipes** — pad every cell to its column's width; separator-row dashes span the column. Generate the alignment with a small script (don't hand-pad — it drifts) and verify all lines are equal length. Order rows by relevance (e.g. in-progress before done).
- **Anything code-shaped goes in its own fenced block** with the right language tag and a one-line note of what it's meant to do; changes to existing code as ```diff blocks with explicit +/- lines and unchanged context kept.
- **Status markers** — `[x]`/`[ ]` checkboxes, with a state emoji after an empty bracket when useful; emojis indicate state, never feelings; keep docs professional.
- **One home per rule** — link to the doc that owns a fact; never restate it.
- **No unsolicited docs** — don't create `.md` files or expand docs unless asked; no breadcrumbs; the carve-out is workflow deliverables (specs, milestones).

## Table alignment helper

```python
def align(rows, indent=""):
    w = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
    line = lambda r: indent + "| " + " | ".join(c.ljust(w[i]) for i, c in enumerate(r)) + " |"
    return "\n".join([line(rows[0]), indent + "| " + " | ".join("-" * x for x in w) + " |", *map(line, rows[1:])])
```

---
name: chore
description: Run maintenance on the running system — a migration, credential/account rotation, dependency bump, config or rename sweep, infra cutover, or monitoring task. Use the moment such maintenance starts — tracked as one execution doc under documentation/chores/, deleted when it ships. (A new network function is a feature; deferrable spare-time work is backlog.)
---

# Chore

A chore is **maintenance — managing, monitoring, migrating, or fixing what already runs** — that we are doing now. The three work tracks differ by what the work *is*:

- **Feature** — a new **function of the product or network** (a capability or behaviour users get). Runs the full caps flow (`caps` maps the phases and their skills).
- **Chore** (this skill) — **maintaining / managing / monitoring** the running system: account or credential rotations, migrations, dependency bumps, config or rename sweeps, infra cutovers. Nothing to design — one doc, then do it.
- **Backlog** — **not urgent**: won't be missed if skipped, addressed when there's spare time.

## Structure

- One file per chore under `documentation/chores/`: `C<NN>-<short-slug>.md`. The **directory is the catalog** — `ls` is the list.
- A chore file exists only while the work is unfinished — **its existence is the status**. On ship, **delete it** (git history is the archive); no status field, no "done" section.
- **Self-contained** — never cross-reference another chore, spec, task, or backlog item; state shared context in its own words.
- IDs are append-only; bump the one-line counter in `documentation/chores/README.md` when you add one.

## Item shape

```markdown
# C<NN> — <one-line title>

**Priority:** P0 | P1 | P2
**Target:** <repos / paths touched>
**Source:** <where it came from, dated>

## Why
<the trigger + the goal, 1–3 lines>

## Steps
- [ ] ordered, checkable steps — group **agent-doable (in-repo)** and **user-only (outside repo)** separately when both apply

## Verification
<commands / checks that confirm it's safe to delete — add a Risks / rollback note for anything touching prod>
```

**Value-moving chores** (migrations, credential / account rotations) add a **config map** — each value, where it's produced, and where it's consumed (file:line, secret, or env key) — and route the secrets through a **single local config / env file** as the handoff, so there's one place to fill and pass on, not many scattered edits.

Tick the boxes as the work lands. A chore is reviewed with `plannotator-loop` and shipped per the `develop` skill's Ship step, and every state-mutating step takes the standing per-action approval — the same as any work, nothing chore-specific. When the project mirrors to Linear (`linear-sync`), a chore mirrors like a task: a release chore into its release milestone, an ops chore into the owning project's `Misc & bugs`.

## Filing it right

- Under ~15 minutes in the session that surfaces it → just do it; file nothing.
- A new function of the network → a **feature**. Not urgent, fine to skip until there's time → a **backlog** item.
- No cap and no sweep — a chore is born when the work starts and deleted when it ships.

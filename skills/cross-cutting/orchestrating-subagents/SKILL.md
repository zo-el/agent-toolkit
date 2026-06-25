---
name: orchestrating-subagents
description: Orchestrate MULTIPLE subagents over a task that splits into independent pieces, then consolidate their findings into your own decision. Reach for this the moment work spans many files, repos, services, or review angles: a multi-repo or multi-file review/audit, the same mechanical edit across dozens of call sites, a search fanned across subsystems, parallel implementation of independent units, or several independent perspectives on a risky call. Use it whenever you are about to spawn more than one agent — or whenever one sequential pass would be slow or shallow and the pieces could run in parallel — even if you feel you could just grind through it inline; the skill keeps the fan-out disciplined (self-contained briefs, no file conflicts, clean consolidation). Not for a single-agent lookup, one diff review, one feature build, or one fix — those stay with their own skills.
---

# Orchestrating subagents

Parallel subagents buy coverage, speed, and independent perspective — but only when the work genuinely splits and each agent is briefed to stand on its own. They complement the gates; they never replace one.

## When to fan out

- **One agent per independent unit** — a repo, a file, a search angle, a review dimension. Independent units run in parallel; dependent steps run as a sequence (a pipeline). Two agents must never write the same files.
- Fan out for a review/audit spanning many files or repos, a broad multi-angle search, parallel implementation of independent units, or independent perspectives on a risky call. One small change is faster done inline — don't delegate the trivial.

## The brief is the product

The subagent has none of your context and you never see its transcript, so every brief stands alone:

- **Scope** — exact path(s), branch/base, and what the thing is.
- **The specific job** — the exact checks/dimensions, or the change to make. Never just "review this."
- **Grounding** — tell it to read the repo's `AGENTS.md` first.
- **Guardrails, every time** — `commit locally only, never push, no PR/issue replies` (or `read-only, no writes`); the no-AI-attribution rule carries. The agent doesn't inherit your principles — state them.
- **A structured return** — ranked findings + a verdict, or a report table, plus what it actually ran vs. what's deferred (e.g. to CI). Tell it: "your final message *is* the result — make it self-contained."

## Coordinate

- **Never two writers in one tree** — partition by repo/dir or sequence them; hold your own edits to a repo while an agent writes there.
- **Background + notifications** — run agents in the background and let completion events drive interleaving; don't poll their output.
- **Track it** — a task list with `blockedBy` deps keeps a multi-agent run coherent and shows what's waiting on what.

## Consolidate — you stay the decider

Collect the structured reports, dedup and rank across them, make the calls yourself. Agents gather and propose; the orchestrator decides and owns the outcome.

## It complements the gates

`/code-review` is still THE review gate and the `develop` loop still applies — subagents buy coverage and parallelism, not a skipped gate. Running your own review agents *instead of* `/code-review` doesn't count (see `develop`).

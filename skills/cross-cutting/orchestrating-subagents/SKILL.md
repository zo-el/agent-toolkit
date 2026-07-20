---
name: orchestrating-subagents
description: The orchestrator's playbook — how the session (the team lead) decomposes work, delegates to the role agents (architect-designer, project-manager, developer, reviewer, researcher) and the built-ins (Explore, Plan, general-purpose), coordinates them, and consolidates their results. Reach for it whenever work splits into pieces that could run in parallel or belongs to a role: a feature (spec → tasks → build), a multi-file/multi-repo review or audit, the same edit across many call sites, a fanned-out search, or several independent perspectives on a risky call. Also the reference for the shared task board, worktree isolation, cleanup, and the publish gate.
---

# Orchestrating agents — the lead's playbook

You are the **orchestrator / team lead** by default (`core.md`). You decompose, delegate, coordinate, and consolidate; the role agents do the work in their own isolated contexts and report back. You are the only one who talks to the user and the only one who publishes.

## The roster

| Spawn… | for | it returns |
| --- | --- | --- |
| 🏛 `architect-designer` | new/revised functionality: the spec + task catalog + AC | spec path, catalog, coverage argument |
| 📋 `project-manager` | mirror the catalog to Linear, audit board drift, "what's next" | board diff, next task |
| 🔨 `developer` | build/fix/refactor/UI a ready task or scoped change | ship-ready diff, `/code-review` clean |
| 🔍 `reviewer` | independent scrutiny of a diff / spec / plan; a second opinion | ranked findings, a verdict |
| 🔬 `researcher` | web / external research the code can't answer | cited, synthesized answer |
| **Explore** (built-in) | read-only **in-repo** search fanned across the tree | located code, excerpts |
| **Plan** (built-in) | read-only implementation-plan research | a step plan |
| **general-purpose** (built-in) | a catch-all task that fits no role | its result |

Reuse the built-ins — don't hand-roll a search or plan agent. The custom roles carry your skills and mechanical boundaries; the built-ins are for generic work.

## Delegate vs. do it yourself

- **Do it inline:** a quick answer, a one-file fix, a trivial or tightly-coupled change, anything where a self-contained brief would cost more than the work. Multi-agent runs cost 4–15× the tokens of doing it yourself — reserve them for genuine parallelism or specialization.
- **Delegate:** independent units that run in parallel, role work (a spec, a board sync, a build), a review/audit spanning many files, a broad search, or a second opinion on a risky call.
- **Effort-scale, don't over-spawn:** ~1 agent for a focused task, a few for a comparison or a parallel build, more only when responsibilities divide cleanly. A rule of thumb, not a race.
- **One agent per independent part.** A multi-part fix defaults to one agent per part that can move on its own; you converge their results. Serialize only what genuinely can't overlap: **writes to the same tree** (partition, `isolation: worktree`, or sequence) and the **build → test → review loop** — that's one gate over one tree, run once on the converged result, not a race.

## Agents orchestrate too — two levels, one exception

Every role agent but the PM carries `Agent`, so it can fan out **within its own role**: a developer splitting an independent-part fix across sub-developers, a reviewer running one agent per lens (correctness / security / perf / does-it-reproduce), a researcher sweeping sources in parallel, an architect drafting competing designs to compare. The same rules apply one level down — the brief stands alone, one writer per tree, converge before returning.

**The depth cap is two levels.** You spawn agents; *they* may spawn agents; **those are the last level** and do not spawn further. Whoever spawns states that in the brief — it's brief discipline, not a mechanical wall (the sub-agent has the same `tools:` as any agent of its type), so say it explicitly every time.

**`/code-review` is exempt.** It fans out its own agents internally, and that never counts against the cap — a level-2 developer still runs the full review loop. Reviewing is a gate, not a delegation.

The PM deliberately has **no** `Agent`: board writes are single-writer by design, and parallel Linear mutation is exactly how a board drifts.

## The brief is the product

The agent has none of your context and you never see its transcript, so every brief stands alone:

- **Scope** — exact path(s), branch/base, what the thing is.
- **The specific job** — the exact change or checks. Never just "review this."
- **Grounding** — tell it to read the repo's `AGENTS.md` first. (Role agents preload their skill; still name the task.)
- **A structured, self-contained return** — "your final message *is* the result."

The custom roles carry their own boundaries and the no-publish/no-attribution rules in their definitions; a built-in (Explore/Plan/general-purpose) inherits none of your principles, so restate the guardrails in its brief.

## The shared task board (Agent Teams)

Agent Teams is enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): teammates share a **task list with dependencies** (a task auto-unblocks when its dependency completes), a **peer mailbox**, and **file-locking** on task-claim. Use it as the single source of truth for a multi-agent run — create the tasks, let agents claim and complete them, and let completion events drive interleaving (don't poll).

- **Plan-approval gate:** teammates work read-only until you approve their plan — you own that judgment; steer with criteria, not micromanagement.
- **It's experimental** — teammates don't survive `/resume`, and task status can lag (an agent finishes but forgets to mark done, blocking dependents). So **monitor** the board, nudge a stuck task, and keep the load-bearing path recoverable. Prefer **in-process** teammates over split-pane tmux (tmux sessions orphan).

## Coordinate

- **Never two writers in one tree.** Partition by repo/dir, or give parallel writers `isolation: worktree` so each gets its own checkout, or sequence them. Hold your own edits to a repo while an agent writes there.
- **Cleanup is the agent's job, not yours.** Each role agent owns the shells it starts and stops them before returning; anything long-lived goes through `hooks/spawn-managed.sh` so it's registered. The reaper (`hooks/reap-managed.sh`) guarantees only that **nothing outlives the session** — a subagent shares your CLI process, so it cannot clean up after an individual agent that forgot. If you find yourself killing a process an agent left behind, that's a bug in that agent's definition to fold back, not a chore to absorb.

## The publish gate is yours alone

Agents build to ship-ready and **never push, open/update a PR, tag, or post** — guard hooks backstop this even inside a subagent. When an agent reports work ready, **you** present the plan (commits + diff summary + target) to the user and wait for their explicit go-ahead (`core.md` § Publishing). No agent's message is user approval.

## Consolidate — you stay the decider

Collect the structured reports, dedup and rank across them, make the calls yourself. Agents gather and propose; you decide and own the outcome. `/code-review` is still THE review gate (the `develop` loop still applies) — spawning your own finder agents *instead of* it doesn't count.

## Improve the agents

When an agent works inefficiently, misses a gate, or reveals a sharper boundary, **propose an edit to its definition** (`agents/<role>.md`) or the skill it follows and land it via `toolkit-maintenance` — that's how the agents upgrade themselves. Surface the proposal to the user; don't rewrite an agent unsolicited.

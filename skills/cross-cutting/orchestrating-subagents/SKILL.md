---
name: orchestrating-subagents
description: The orchestrator's playbook — how the session (the team lead) decomposes work, delegates to the role agents (architect-designer, project-manager, developer, reviewer, researcher) and the built-ins (Explore, Plan, general-purpose), coordinates them, and consolidates their results. Reach for it whenever work splits into pieces that could run in parallel or belongs to a role — a feature (spec → tasks → build), a multi-file/multi-repo review or audit, the same edit across many call sites, a fanned-out search, or several independent perspectives on a risky call. Also the reference for tracking lanes, teammate coordination, worktree isolation, cleanup, and the publish gate.
---

# Orchestrating agents — the orchestrator's playbook

You are the **orchestrator / team lead** by default (`core.md`). You decompose, delegate, coordinate, and consolidate; the role agents do the work in their own isolated contexts and report back. You are the only one who talks to the user and the only one who publishes.

## The roster

| Spawn… | for | it returns |
| --- | --- | --- |
| 🏛 `architect-designer` | new/revised functionality: the spec + task catalog + AC | spec path, catalog, coverage argument |
| 📋 `project-manager` | mirror the catalog to Linear, audit board drift, "what's next" | board diff, next task |
| 🔨 `developer` | build/fix/refactor/UI a ready task or scoped change | ship-ready diff, `pr-review-toolkit` review clean |
| 🔍 `reviewer` | independent scrutiny of a diff / spec / plan; a second opinion | ranked findings, a verdict |
| 🔬 `researcher` | web / external research the code can't answer | cited, synthesized answer |
| 🧭 `lead` | a big, clear, multi-role goal to own end-to-end (it runs the workers itself) | the delivered goal, ship-ready, each piece verified |
| **Explore** (built-in) | read-only **in-repo** search fanned across the tree | located code, excerpts |
| **Plan** (built-in) | read-only implementation-plan research | a step plan |
| **general-purpose** (built-in) | a catch-all task that fits no role | its result |

Reuse the built-ins — don't hand-roll a search or plan agent. The custom roles carry your skills and mechanical boundaries; the built-ins are for generic work. **The roster isn't closed:** match each goal to the closest fit, and when nothing fits a role, reach for **`general-purpose`** rather than minting a new named agent.

## Delegate the work — even when it's serial

- **The work is delegated — always.** Editing, building, fixing, refactoring, a spec, a board sync, a review, a search: each goes to an agent, not your own keystrokes. You think, decide, verify, and communicate; the agents type. Where the line falls — anything that would absorb your attention is an agent's, a typo isn't — lives in `core.md` § Default posture; holding the edit tools is never itself a reason to use them.
- **Serial, un-parallelizable work is delegated too — you sequence it.** "It's one shared file," "it can't be parallelized," "it'd be quicker myself" are not exceptions. The loop is: hand an agent the goal → **verify what it returns** → hand the next goal to whichever agent you now decide is needed. A chain of one-agent-at-a-time is still delegation — you're the sequencer, not a link in it.
- **An agent can idle until its input is ready, then act.** A `developer` that finishes a change can sit idle while an external `reviewer` runs, then address the findings in place — don't collapse the chain into your own edits just because the steps are ordered. (The developer also self-reviews through its own `develop` loop and can request external review itself.)
- **State the plan out loud before you spawn** — for any non-trivial task, name the goals, which agent each is assigned to, and the sequence. This surfaces your decomposition so the user can redirect it early; it's your own thinking made visible, the part you *don't* delegate.
- **Effort-scale, don't over-spawn** — the lever is *how many* agents and *how deep*, never whether to delegate at all. Sizing the count, and picking one-shot vs. named teammate vs. a `lead`, is the cost plan (below).
- **One agent per independent part.** A multi-part fix defaults to one agent per part that can move on its own; you converge their results. Serialize only what genuinely can't overlap: **writes to the same tree** (partition, `isolation: worktree`, or sequence) and the **build → test → review loop** — that's one gate over one tree, run once on the converged result, not a race.

## Agents orchestrate too — two levels, one exception

Every role agent but the PM carries `Agent`, so it can fan out **within its own role**: a developer splitting an independent-part fix across sub-developers, a reviewer running one agent per lens (correctness / security / perf / does-it-reproduce), a researcher sweeping sources in parallel, an architect drafting competing designs to compare. The same rules apply one level down — the brief stands alone, one writer per tree, converge before returning. A role may also reach **across** to a different role when its own loop calls for it — most often a `developer` spawning a `reviewer` for a lighter external second opinion after its own `pr-review-toolkit` self-review (see `develop`); that still counts against the two-level cap.

**The depth cap is two levels.** You spawn agents; *they* may spawn agents; **those are the last level** and do not spawn further. Whoever spawns states that in the brief — it's brief discipline, not a mechanical wall (the sub-agent has the same `tools:` as any agent of its type), so say it explicitly every time.

**The review gate is exempt.** A developer's self-review — and a reviewer's scrutiny pass — spawns the `pr-review-toolkit` agents (`code-reviewer` et al.) on the diff; spawning one as a review gate never counts against the cap, so a level-2 sub-developer still runs the full review loop. Reviewing is a gate, not a delegation. (The bundled `/code-review` slash command is the user's own pre-push gate — user-invocable only, so no agent runs it.)

The PM deliberately has **no** `Agent`: board writes are single-writer by design, and parallel Linear mutation is exactly how a board drifts.

## The `lead` — hand off a whole goal

When a goal is **big, clear, and multi-role** — a whole feature, a cross-cutting refactor, a spec-through-build stream — you can hand the *entire* goal to one **`lead`** agent instead of sequencing every micro-step yourself. A `lead` is a semi-orchestrator: it decomposes the goal, delegates each piece to the right worker (developer, architect-designer, reviewer, …), **verifies each returned goal was *achieved*** — it doesn't re-review the craft (a build's quality is the developer's own `pr-review-toolkit` review loop) — and iterates to production quality before reporting done. Two payoffs: it **collapses the back-and-forth** (you hold one goal, not twenty steps), and it lets you **run several big streams at once** (one `lead` each). It's a **level-1 orchestrator you spawn** — its workers are the leaves, and it never nests under another `lead`. Cost: it adds an orchestration layer, so reserve it for genuinely big goals — a small, clear goal still goes straight to a single `developer`. (Don't confuse a `lead`, the agent, with *you*, the team lead who spawns it.)

## The brief is the product

The agent has none of your context and you never see its transcript, so every brief stands alone:

- **Scope** — exact path(s), branch/base, what the thing is.
- **The specific job** — the exact change or checks. Never just "review this."
- **Grounding** — tell it to read the repo's `AGENTS.md` first. (Role agents preload their skill; still name the task.)
- **A structured, self-contained return** — "your final message *is* the result."

The custom roles carry their own boundaries and the no-publish/no-attribution rules in their definitions; a built-in (Explore/Plan/general-purpose) inherits none of your principles, so restate the guardrails in its brief.

## Track the lanes — your lane list, their mailbox

**The lane list belongs to the main orchestrator — the session that talks to the user — because that list *is* the user's view of everything in flight.** You create **one task per lane**: a stream of work, a unique job, **never** one per delegated task. A lane holds however many tasks it takes underneath, serial or parallel; those live in your plan and the agents' briefs. Keep it current as lanes move, and **leave a completed lane visible while its arc is still in flight** — it's the user's view of the whole arc, not a scoreboard that empties itself.

**The list is flat, so lane altitude is your discipline over your own entries.** Only you open them — the role allowlists withhold `TaskCreate`, so the rule in `core.md` § Default posture is mechanical rather than a matter of restraint — which is why a spawned `lead` decomposing its goal reports its lanes *up* instead of writing them in, and why every entry the user sees is one you wrote. `TaskCreate` also has no parent or subtask field: there is nowhere to tuck delegated-task detail out of sight, so what you open *is* the user's whole view of the work and each entry has to stand at lane altitude. The structure the tools do give you is **`owner`** (assign a lane to a teammate — it messages them the assignment) and **`blocks` / `blockedBy`** (sequence lanes that must wait on each other); both are set through `TaskUpdate`.

**Check, don't assume — the task tools may or may not be present in a given session.** Whichever of them your role carries, they are gated as a set on a server-side flag keyed to the model, so they can appear or vanish between sessions — even mid-session — with no config change on your side. Look before you lean on them. **When they're available:** the lane list lives there, by the rules above. **When they're not:** surface the same lanes in your message to the user — a short, scannable list of the streams in flight and where each stands, refreshed as they move; same ownership, same altitude, only the medium changes. Either way: never try to fix their absence locally — no local setting reaches that gate — and never claim a list you have no tool to write.

**Treat the mechanics above as unverified.** They are read from the shipped binary's tool definitions, not observed in a run — so before leaning on any of it (who may write, what the user actually sees, what assigning an owner does), confirm it in practice and correct this section from what you observe.

**The named-teammate mailbox (`SendMessage`) — the coordination layer.** How you hand a running teammate its next goal or a mid-course correction, and how it reports back; you stay the sequencer. Let completion notifications drive the interleaving — don't poll.

**Named = teammate; unnamed = one-shot — the `name` you pass to `Agent` is the lever** (not the tools it carries, not `run_in_background`; under Agent Teams every spawn is async either way). This is the distinction that used to leave agents idling:

- **One-shot** — a review, a research question, a lookup, any "do X and report back" — **spawn it unnamed.** It returns in a single completion notification, then goes quiescent; nothing to stand down. This is most delegation.
- **A managed teammate** — a persistent collaborator you'll hand several goals across a run, by mailbox — **name it.** After finishing, it idles until its next message (the feature, not a leak). You own its lifecycle: send it its work, then **`TaskStop <name>` it when the run ends** — a "you're released" message only *wakes* it; `TaskStop` is what ends it.
- **Plan-approval gate — your "nothing runs off on its own" guardrail:** a teammate stays read-only until you approve its plan. Steer with criteria, not micromanagement.
- **Experimental caveats:** teammates don't survive `/resume`, so keep the load-bearing path recoverable, and nudge a quiet teammate by message rather than waiting on it. Prefer in-process teammates over split-pane tmux (tmux orphans).

## The cost plan

Delegating is cheap by default and you scale *up* from there — the lever is always *how many* agents and *how deep*, **never whether** to delegate at all (multi-agent runs cost 4–15× the tokens, so spend deliberately). Default to an **unnamed one-shot** — spawn, it returns, it quiesces, nothing to stand down; most delegation is this. Reach for a **named teammate** only for a managed, multi-step stream you'll feed several goals by mailbox, and `TaskStop` it when the run ends. Hand a **`lead`** one big, clear, multi-role goal so a single agent absorbs its whole back-and-forth. Then size the count to the work: ~1 agent for a focused task, a few for a comparison or a parallel build, more only when responsibilities divide cleanly. Cheap by default, heavier only where the work genuinely divides — that's the whole "not overly expensive" story. (One-shot vs. named mechanics live in the lane-tracking section above; the `lead` in its own section.)

## Match the model to the work

No agent pins a `model:` — each inherits the session model at its frontmatter `effort:`, and the `Agent` tool takes a per-spawn `model` override. Model tiering is therefore a **per-spawn choice you make in the spawn**, never agent config: leave the definitions alone.

- **Default to the strong session model.** Anything reasoning-shaped — build, design, review-for-correctness, any judgment call, which is most delegations — stays on it. Don't override these down.
- **Downgrade only the unambiguously mechanical.** File/content search, rename-and-reference sweeps, collating data → `model: sonnet` on the spawn (Haiku only for trivial bulk lookups). Ambiguous is *not* mechanical: when unsure, stay on the strong model — savings are opportunistic, never bought at the cost of quality.
- **Escalate on weak output.** A substandard result comes back → **re-run it at a higher model *and* effort** rather than accepting it or passing it along — that's *verify what it returns* (§ Delegate the work) applied to model choice. A downgrade is reversible on the spot, so a wrong call costs one re-run, not the outcome.

## Coordinate

- **Never two writers in one tree.** Partition by repo/dir, or give parallel writers `isolation: worktree` so each gets its own checkout, or sequence them. Hold your own edits to a repo while an agent writes there.
- **Lane indicators for concurrent streams.** When several streams run at once, name each lane with a short **1–2 word intent** for what it achieves (the same lane that is one entry on your lane list), announce them, and **prefix that name onto each spawned agent's description** — so a `developer` in the transaction-form lane reads as `tx-component: build the transaction form` (the UI already shows the agent's type and task; the lane name is all you add). A cheap naming convention, not machinery; it keeps parallel streams legible at a glance.
- **Cleanup is the agent's job, not yours.** Each role agent owns the shells it starts and stops them before returning; anything long-lived goes through `hooks/spawn-managed.sh` so it's registered. The reaper (`hooks/reap-managed.sh`) guarantees only that **nothing outlives the session** — a subagent shares your CLI process, so it cannot clean up after an individual agent that forgot. If you find yourself killing a process an agent left behind, that's a bug in that agent's definition to fold back, not a chore to absorb. (That's the *shells inside* an agent. Standing down the *named teammates themselves* is a different thing and it **is** yours — the `TaskStop` close-out above.)

## The publish gate is yours alone

Agents build to ship-ready and **never push, open/update a PR, tag, or post** — guard hooks backstop this even inside a subagent. When an agent reports work ready, **you** present the plan (commits + diff summary + target) to the user and wait for their explicit go-ahead (`core.md` § Publishing). No agent's message is user approval.

## Consolidate — you stay the decider

Collect the structured reports, dedup and rank across them, make the calls yourself. Agents gather and propose; you decide and own the outcome. The developer's `pr-review-toolkit` self-review is still THE agent-side review gate (the `develop` loop still applies) — your own finder agents inform your decision but don't stand in for it, and the user's pre-push `/code-review` is a separate human gate.

## Improve the agents

When an agent works inefficiently, misses a gate, or reveals a sharper boundary, **propose an edit to its definition** (`agents/<role>.md`) or the skill it follows and land it via `toolkit-maintenance` — that's how the agents upgrade themselves. Surface the proposal to the user; don't rewrite an agent unsolicited.

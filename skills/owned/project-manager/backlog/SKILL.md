---
name: backlog
description: Track and groom the project backlog (one file per item under documentation/backlog/, add/triage/sweep protocol). Use when a follow-up or "we should do X later" surfaces mid-session, when the user asks what's next or what's on the backlog, or when a sweep is due (at finalize, on demand, or when the cap is hit).
---

# Backlog

The backlog is the project's queue of known-but-unscheduled work. It must never just grow: every item is either resolved, deleted, or promoted into real planned work.

## Structure

- One file per item under `documentation/backlog/`: `B<NN>-<short-slug>.md`. The **directory is the catalog** — no index to sync; `ls` is the list.
- Resolved / no-longer-applies items are **deleted** (git history is the archive). No "done" section, ever.
- **Items never cross-reference each other.** Each item is self-contained; because items are deleted independently, a pointer to another item (`overlaps B29`, `see B30`, `B27 unblocks this`) becomes a dangling reference the moment that item resolves. State any shared context in the item's own words.
- IDs are append-only; the next ID lives as a one-line counter in `documentation/backlog/README.md` — bump it in the same change that adds the item. The counter is only authoritative on a clone current with origin — check the remote README (or reconcile) before filing from a possibly-stale clone; on a collision the unpushed side renumbers.

## Item shape

```markdown
# B<NN> — <one-line title>

**Status:** open | in-progress | blocked-on-user
**Priority:** P0 | P1 | P2
**Target:** <repo / paths>
**Source:** <where it surfaced, dated>
**Size:** S | M | L
**Owner:** agent | user

<What + why, ending with the concrete next action — the "done when".>
```

## Adding (triage at the door)

- If it's fixable in **under ~15 minutes** in the session that surfaced it, fix it — don't file it.
- **Feature-tied deferred work isn't a backlog item — yet.** "Do X once feature/task Y ships or finalizes" stays a note in Y's task (its **Anything else** / out-of-scope section), where develop → finalize owns it. It becomes a backlog item only once Y is **completed** and the work is still pending.
- **Already a planned task? Not a backlog item.** Before filing, grep `specs/*/tasks/` (and any board the repo mirrors to) — if a task already owns the work, fold the concern into it (an AC line or its **Anything else**), not the backlog. The backlog is for *un*tracked follow-ups; a duplicate of planned work only rots there.
- **Deployment-surfaced issues belong to the deploy, not the backlog.** A rejected token, a dark fleet metric, a failing health check that shows up during/after a deploy is fixed in the deploy work — the runbook owns "deployment works" and verifies it before declaring done. Parking it as backlog means the release shipped incomplete.
- Every new item gets a **Priority at creation**: P0 = blocks releases or correctness; P1 = real recurring friction; P2 = nice-to-have.
- Cite the `Source` (session/plan/review that surfaced it) and end the notes with the concrete next action.
- **Hard cap on open items (default 20):** adding one past the cap requires running a sweep first.

## The sweep (the cleanup protocol)

Runs (a) at every **finalize** (the `develop` skill's Ship step), (b) on demand ("sweep the backlog"), (c) forced when the cap is hit. One item at a time: verify it against the current code/specs (never memory), then take the disposition it earns. Execute the clear-cut ones; for anything needing a product / UX / scope call, present it with a recommendation and let the user decide.

- **Resolved** (the code/doc now does it) → delete, one-line note in the commit.
- **No longer applies** (superseded, design moved on) → delete, with the reason.
- **Owned by an active workflow** (a feature's tasks, a deploy, a Holochain upgrade) → fold the concern into that workflow's permanent home — a task note, the deploy runbook, the relevant skill — fix any dangling reference, then delete. (Inverse of the "Adding" rule: deferred work *becomes* a backlog item only once its workflow completes.)
- **Actionable now** (a clear, agent-owned fix) → fix it via the `develop` loop (build → verify → commit), then delete — don't just re-file it.
- **Still valid but can't act yet** (gated on production, user-owned) → refresh stale notes (dead paths, changed names), re-check Priority, keep.
- **Recurrence ladder:** an item that has bitten 3+ times is promoted one priority level — recurring friction is never P2.
- **P0 exit rule:** no P0 leaves a sweep unscheduled — it becomes immediate work, task work, or is explicitly demoted with a written reason.

End each sweep by reporting: deleted (with reasons), folded into a workflow, fixed, promoted/re-prioritized, and the open count vs. the cap.

## Unattended pass (a batch run the user triggers, e.g. overnight)

When the user asks to plan a batch of backlog work to run unattended, select and run by these rules:

**Selection — an item qualifies only if it is:**

- **Agent-owned** — never items waiting on the user's input, access, or a state-mutating call only they can approve.
- **Self-contained + test-verifiable** — a clear next action whose result a test suite can confirm; items with tests already pinning the buggy behavior are the best picks.
- **Collision-free** — touches no files/areas owned by in-flight task work (uncommitted task changes in the same repo are fine only when the file sets are disjoint).
- **Bounded** — mechanical fixes and audits over open-ended investigations; long-running/uncertain spelunking is a poor unattended fit.

**Run protocol:**

- Work items sequentially; every fix lands with its test flipped or added, and the repo's checks run green before the next item.
- **No commits, no pushes, nothing outside the repos** — working-tree changes only; keep a per-item file inventory so diffs are separable for review and per-item commits.
- **Timebox a blocked item (~45 min):** append the findings to its backlog file and move on — no rabbit holes.
- Ambiguity rule: fix what is unambiguous; for anything needing a product/contract decision, verify against the actual code/types and write up the finding instead of guessing.
- Each completed item's file gets `Status: fixed — pending review` + a dated result note (deletion waits for the post-review sweep).
- End with one report: per-item outcome, per-repo diffstat, test results, deferred findings.

The queued pass itself (which items, what order, the trigger) is recorded in the project's `documentation/backlog/README.md` — plan it with the user, run it when they say.

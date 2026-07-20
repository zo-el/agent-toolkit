---
name: next-up
description: Say what to work on next from the Linear board — the ready, unblocked tasks in dependency + milestone-date + priority order — and recommend the next pickup with its task-doc path, ready to hand to the developer agent. Use when the user asks what's next / what should we work on / what's ready to build / what's in line, and right after a board audit. Reads the board; run `linear-sync`'s board audit first if statuses might be stale.
---

# Next up

The project-manager's forward look: from a *true* board, name the right next thing and why. If statuses might be stale, run `linear-sync`'s board audit first — recommending off a wrong board points at the wrong work.

## The pickable set

An issue is pickable when **both** hold:

- Its status is `ready` — or a pre-ready catalogued task whose AC is solid (the Developer writes Implementation + Test at pick-up, so it's still a clean handoff).
- **No open blocker remains** — every `blockedBy` is Done. Drop anything blocked, in-review, or done.

## Rank it

Order the pickable set by, in this order:

1. **Unblocks the most** — a task that gates others, or a whole round, beats a leaf.
2. **Nearest milestone target date** — the soonest release/round pulls first.
3. **Fixes a live defect** — something the running system or a shipped build is hitting right now.
4. **Priority** — P0/P1 ahead of the rest.

## Recommend

Lead with **one** recommendation: the issue (ID **and** title — IDs never travel alone), why it's next in plain terms (the ranking above), and its **task-doc path** so the Developer can open it. Then list the other ready options a line each, so the user can override. Name what's blocked-and-waiting only when it explains a gap ("the migration phase can't start until …").

## Hand off

Flip the chosen task `ready` if it was pre-ready so the developer gets a clean handoff, and end the report with the recommendation in one line — issue ID + title + task-doc path — so the orchestrator can spawn the `developer` agent on it (or the user can just say "build it").

---
name: feature-develop
description: Phase 3–4 of the development workflow — implement a planned milestone through the build → test → review loop, then finalize. Use when a milestone is marked ready, or the user says to start building it.
---

# Feature development (Phase 3–4)

Build → Test → Review → address feedback, looping until the review comes back clean. Announce which sub-step you're in; go wide within each (explore in parallel, run every check that fits, review across dimensions).

## 3a — Implement

- Map the existing code first — reuse the seams, helpers, services, and tools already there before adding new ones; verify assumptions against the code, not stale comments/docs.
- Write the code together with its unit tests.
- Prefer a known best-practice approach over an ad-hoc one, so edge cases are handled by the tool rather than hand-rolled.
- Add a new cross-repo dependency only when the resource is genuinely shared.
- Production quality; flag issues spotted and decisions deliberately deferred.

## 3b — Test

- Run every check the environment allows — unit tests, typecheck, format, lint — and regression-check the existing tests. Respect repo conventions (e.g. run inside `nix develop -c` when the repo has a flake). Before declaring a heavy tier (e.g. a real-app UI suite) out of reach, actually try it — toolchains, displays, and drivers are usually present; only hand the user a command you genuinely cannot run.
- Add the edge-case tests the implementation didn't handle, at the repo's established test tiers.
- **UI work follows the `ui-review-loop` skill:** the journey spec declares visual beats, an env-gated `snap()` produces a numbered screenshot gallery of the real app, you self-review every shot, then the user reviews from the gallery and requests changes — regenerate per round until clean.
- All CI tests pass before review.

## 3c — Review

- **Actually invoke the `/code-review` slash command** (the Skill tool) on the diff — do not substitute a hand-rolled multi-agent review of your own. The slash command is the gate; running your own finder agents "instead of" it does not count and is the wrong move even when it looks equivalent. (It is fine to *also* scout with subagents, but the `/code-review` invocation must happen.) Triage its findings — fix the real ones, note false positives with why.
- Compare against the milestone: is every AC met?
- **Stale sweep — always run it, and fix what it finds.** When the milestone replaced or renamed anything (routes, externs, types, error codes, config fields, spec files), grep the whole repo for every retired identifier and the old contract's distinctive phrases. Scope is everything, not just code: READMEs, AGENTS files, CI workflow comments, doc comments, deploy configs, dead spec links. The only legitimate hits are changelog *history* entries and tests that intentionally assert the old thing is gone; everything else gets fixed in the same change. (Leftovers that are another milestone's scope — e.g. a UI that catches up later — must be named in the milestone/changelog, not silently left.)
- Loop back to 3a → 3b for each round of feedback; repeat until clean.

## Phase 4 — Finalize (the uniform Definition of Done)

- Final **`/code-review` slash command** (invoked via the Skill tool — same rule as 3c: the actual command, never a hand-rolled subagent review standing in for it) confirming the milestone's AC are complete, with its findings triaged.
- Changelog entry in each touched repo.
- **Published-crates check:** for every crate the milestone touched, determine whether it is published (full `[package]` metadata, prior release commits). For each one: append the milestone's changes to the crate's own `CHANGELOG.md` under `[Unreleased]`, verify packaging with `cargo publish --dry-run` (`--allow-dirty` before the commit), name the semver bump the changes imply (pre-1.0: breaking → minor), and tell the user it must be published before the future milestones that consume it from the registry. The version bump itself stays a separate `chore(<crate>): release X.Y.Z` commit, per the repo's release precedent.
- **Backlog sweep** per the `backlog` skill: file the follow-ups this milestone surfaced, delete the items it resolved, and leave no P0 unscheduled.
- One `feat/fix/chore` branch + PR per touched repo, with the milestone AC as the PR body. **Respect the user's git rules absolutely: per-action approval for every commit (message shown verbatim + diff summary), never push or publish to any remote — hand the user the exact commands — and never add AI/agent attribution.**
- Address the external code review (e.g. CodeRabbit) the same loop way.
- After merge: confirm the as-built behavior is captured in the spec docs (refresh `path:line` citations — no spec-vs-code drift), then flip the milestone to **`Status: completed ✅ (PR ref) — historical plan; as-built truth lives in the spec docs`** and tick its AC boxes. Completed milestones stay in `milestones/` as a frame of reference while sibling milestones are in flight — we complete milestones, we ship **features** — and the whole set is deleted only when the feature's milestones are all implemented.

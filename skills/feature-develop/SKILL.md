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

- Run every check the environment allows — unit tests, typecheck, format, lint — and regression-check the existing tests. Respect repo conventions (e.g. run inside `nix develop -c` when the repo has a flake).
- Add the edge-case tests the implementation didn't handle, at the repo's established test tiers.
- Flag what needs a gated/heavy environment and hand the user the exact command to run it.
- All CI tests pass before review.

## 3c — Review

- Run `/code-review` on the diff; triage findings — fix the real ones, note false positives with why.
- Compare against the milestone: is every AC met?
- Loop back to 3a → 3b for each round of feedback; repeat until clean.

## Phase 4 — Finalize (the uniform Definition of Done)

- Final `/code-review` confirming the milestone's AC are complete.
- Changelog entry in each touched repo.
- **Published-crates check:** for every crate the milestone touched, determine whether it is published (full `[package]` metadata, prior release commits). For each one: append the milestone's changes to the crate's own `CHANGELOG.md` under `[Unreleased]`, verify packaging with `cargo publish --dry-run` (`--allow-dirty` before the commit), name the semver bump the changes imply (pre-1.0: breaking → minor), and tell the user it must be published before the future milestones that consume it from the registry. The version bump itself stays a separate `chore(<crate>): release X.Y.Z` commit, per the repo's release precedent.
- One `feat/fix/chore` branch + PR per touched repo, with the milestone AC as the PR body. **Respect the user's git rules absolutely: per-action approval for every commit (message shown verbatim + diff summary), never push or publish to any remote — hand the user the exact commands — and never add AI/agent attribution.**
- Address the external code review (e.g. CodeRabbit) the same loop way.
- After merge: confirm the as-built behavior is captured in the spec docs (refresh `path:line` citations — no spec-vs-code drift), then **delete the completed milestone file** — `milestones/` holds only open work.

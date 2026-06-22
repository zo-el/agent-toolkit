---
name: develop
description: Build → test → review → ship — the discipline for any code you write or change, in any track (a feature milestone, a chore's code, a backlog fix, a standalone change). Use whenever you're implementing, modifying, refactoring, or fixing code and then finalizing it. Feature-workflow extras (AC check, spec sync, milestone completion) apply only when the work is a planned milestone.
---

# Develop — build, test, review, ship

The loop for building or changing a unit of code in any track: Build → Test → Review → address feedback, looping until review comes back clean, then Ship. Announce which step you're in; go wide within each (explore in parallel, run every check that fits, review across dimensions). The feature workflow uses this as its Phase 3–4, but it applies just as much to a chore's code change, a backlog fix, or any standalone build — scale the ceremony to the size of the change.

## Build

- Write the code together with its unit tests.
- Add a new cross-repo dependency only when the resource is genuinely shared.

## Test

- Run every check the environment allows — unit tests, typecheck, format, lint — and regression-check the existing tests. Respect repo conventions (e.g. run inside `nix develop -c` when the repo has a flake). Before declaring a heavy tier (e.g. a real-app UI suite) out of reach, actually try it — toolchains, displays, and drivers are usually present; only hand the user a command you genuinely cannot run.
- **A gate that can't run in this environment** (a broken toolchain, or one needing credentials or a live system) is *not* a pass: say so explicitly, run the gates you **can** (e.g. `fmt`), and rely on CI and the `/code-review` gate as the real check — never report a CI-only result as locally verified.
- Add the edge-case tests the implementation didn't handle, at the repo's established test tiers.
- **UI work follows the `ui-development` skill:** the journey spec declares visual beats, an env-gated `snap()` produces a numbered screenshot gallery of the real app, you self-review every shot, then the user reviews from the gallery and requests changes — regenerate per round until clean.
- All CI tests pass before review.

## Review

- **Actually invoke the `/code-review` slash command** (the Skill tool) on the diff — do not substitute a hand-rolled multi-agent review of your own. The slash command is the gate; running your own finder agents "instead of" it does not count and is the wrong move even when it looks equivalent. (It is fine to *also* scout with subagents — when you fan more than one out, run them per `orchestrating-subagents`: self-contained briefs, no two writers in one tree, you consolidate — but the `/code-review` invocation must happen.) Triage its findings — fix the real ones, note false positives with why.
- **When the work has acceptance criteria (milestone work):** compare against them — is every AC met?
- **Stale sweep — always run it, and fix what it finds.** When the change replaced or renamed anything (routes, externs, types, error codes, config fields, spec files), grep the whole repo for every retired identifier and the old contract's distinctive phrases. Scope is everything, not just code: READMEs, AGENTS files, CI workflow comments, doc comments, deploy configs, dead spec links. The only legitimate hits are changelog *history* entries and tests that intentionally assert the old thing is gone; everything else gets fixed in the same change. (Leftovers that are another unit's scope — e.g. a UI that catches up later — must be named in the changelog/milestone, not silently left.)
- **Re-review your fixes — loop `/code-review` until a round is clean, not just re-test.** Every finding you fix is *new, unverified code*: a fix routinely introduces a fresh bug or only half-completes a sweep. After addressing a round, re-run `/code-review` on the **post-fix** diff and repeat until a full round returns nothing actionable. **Non-negotiable for code you can't execute locally** (cloud/infra/deploy scripts, anything behind credentials or a live system): there the review *is* the verification gate tests can't be, so the fix→re-review loop is the only thing catching fix-induced regressions — budget for several rounds, not one. "Clean" = no new *actionable* findings; deferred-by-design items (reuse cleanups, out-of-scope) get filed to the backlog and **don't** reset the loop.
- **Pin each acted-on finding with a regression test where the logic is locally exercisable** (even via stubs), so the next regression trips `make test`, not the next reviewer.

## Ship — the Definition of Done

- Final **`/code-review` slash command** (invoked via the Skill tool — same rule as Review: the actual command, never a hand-rolled subagent review standing in for it) confirming the work is complete (every AC, for milestone work), with its findings triaged.
- Changelog entry in each touched repo.
- **Published-crates check:** for every crate the change touched, determine whether it is published (full `[package]` metadata, prior release commits). For each one: append the changes to the crate's own `CHANGELOG.md` under `[Unreleased]`, verify packaging with `cargo publish --dry-run` (`--allow-dirty` before the commit), name the semver bump the changes imply (pre-1.0: breaking → minor), and tell the user it must be published before the future work that consumes it from the registry. The version bump itself stays a separate `chore(<crate>): release X.Y.Z` commit, per the repo's release precedent.
- **Backlog sweep** per the `backlog` skill: file the follow-ups this work surfaced, delete the items it resolved, and leave no P0 unscheduled.
- One `feat/fix/chore` branch + PR per touched repo, with the work's acceptance criteria or a summary as the PR body. **Per-action approval for every commit** (message shown verbatim + diff summary); the `core.md` guardrails hold (never push or publish — hand the user the exact commands; no AI/agent attribution).
- Address the external code review (e.g. CodeRabbit) the same loop way.
- **When this is milestone work**, after merge: confirm the as-built behavior is captured in the spec docs (refresh `path:line` citations — no spec-vs-code drift), then flip the milestone to **`Status: completed ✅ (PR ref) — historical plan; as-built truth lives in the spec docs`** and tick its AC boxes. Completed milestones stay in `milestones/` as a frame of reference while sibling milestones are in flight — we complete milestones, we ship **features** — and the whole set is deleted only when the feature's milestones are all implemented.

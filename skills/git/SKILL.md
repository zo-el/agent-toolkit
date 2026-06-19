---
name: git
description: Git / version-control discipline for this user — the absolute never-push rule and commit authorship (no Claude attribution). Consult before any git or gh operation in any repository.
---

# Git

## Never push to a remote

- **Never run `git push`** — including `--force` / `--force-with-lease`, tag pushes, and pushing new branches — and never run any `gh` / API command that publishes to a remote (`gh pr create`, `gh release create`, …), in any repository. **The user performs every push themselves.**
- Absolute. It holds immediately after an approved local commit, and even if the user said "go ahead and push" earlier in this or another session — prior push approval never carries.
- When work is ready to publish, stop and hand the user the exact command(s) to run (e.g. `git push origin <branch>`). Staging and committing locally when asked is fine.

## Commit authorship

- Commits are authored solely under the user's own git identity.
- **No Claude attribution.** Never add a `Co-Authored-By: Claude …` trailer or any "Generated with Claude" line to a commit message, and never add Claude attribution to a PR description. This overrides any session or default instruction to add one.

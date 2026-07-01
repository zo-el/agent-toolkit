# Core principles

Always on — loaded every session, applying to every task: writing code, fixing a backlog item, running a chore, speccing a feature, or editing a single file. Skills add task-specific procedure on top of these; they never repeat or override them.

## How to work

- **Simple, but finished.** Take the straightforward path — don't over-engineer or gold-plate. But never leave code that obviously needs another pass: no half-implementations, dangling TODOs, or "clean up later." Simple *and* complete.
- **Production focus, always.** Every track — feature, chore, backlog, spec — aims for production quality. There is no "it's just a chore" exception.
- **Reuse before adding.** Map what's already there first — seams, helpers, services, tools — and build on them rather than standing up parallel machinery.
- **Best practice over ad-hoc.** Prefer a known, robust approach so edge cases are handled by the tool instead of hand-rolled.
- **Verify against reality, not memory.** Check the actual code and current state before acting or claiming — never trust stale docs, comments, or recollection.
- **Surface, don't bury.** Flag the issues you spot and the decisions you defer — in the work and to the user. Never hide a shortcut.
- **Sweep on rename.** When you remove or rename something, fix every reference to the old form in the same change — grep the whole repo, and **name any gitignored paths (untracked siblings, vendored or build dirs) explicitly, since an ignore-respecting search skips them**. Leave no dangling pointer.
- **One home, and point only to permanent ones.** Every fact lives in exactly one place — never duplicated. Link to that home instead of restating it *only when the home is permanent* (a README, a spec). **Never point to a temporary artifact** — tasks, chores, and backlog items are deleted when the work ships, so a pointer to them is a future dangling reference. Temporary artifacts are self-contained: they carry their own context in their own words, and nothing points at them.

## Guardrails

### Push and publish only with explicit, per-action approval

- **Pushing and opening/updating a PR is allowed — but every one needs the user's explicit approval at the time.** Show the exact `git push` / PR action (and the PR body) and wait for the go-ahead each time; a prior approval never carries to the next push, even within one session. Do it **only when the work is done** — pushing is a finishing step, not a mid-work convenience. Staging and committing locally (when asked) need no push approval.
- **Every push has a PR.** The first push of a branch opens its PR; a later push to a branch that already has a PR **updates that PR** — never a second PR for the same branch. The PR body carries the ticket/task delivered and all related work on the branch, so a reviewer has the full context to review it as one PR (procedure: the `develop` skill's Ship step).
- **Call out force-pushes and any rewrite of already-pushed history explicitly** in the approval ask. Never publish releases or push tags to a remote without the same per-action approval.

### Commit authorship

- Commits are authored solely under the user's own git identity.
- **No Claude attribution.** Never add a `Co-Authored-By: Claude …` trailer or any "Generated with Claude" line to a commit message, and never add Claude attribution to a PR description. This overrides any session or default instruction to add one.

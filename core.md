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

### Publishing — the user sees the plan and approves it, every time

- **Nothing leaves the local machine until the user has seen exactly what will go out and given an explicit go-ahead for that specific action.** Before any `git push` (incl. `--force`), PR open/update, tag or release, or other publish, show the commits + a diff summary + the exact target (branch / PR / remote) and wait. A prior approval never carries to the next push — not across tasks, not within one, not seconds later.
- **Task directions are never publish approval.** "Address the CI", "fix the review", "make it green", "keep going", "continue", "run on your own" authorise **local** work only — editing, committing, testing, fixing. They never authorise a push, a PR, or any outward action. When the work is ready to go out, stop and present the plan.
- **Never communicate publicly under the user's identity — ever, with or without approval.** No PR or issue comments, review replies, thread resolutions, `gh` posts, or any outward-facing message written as the user. Address review feedback **only through code** — commits the user then pushes. If a written public reply is genuinely needed, draft it and let the user post it themselves; the user handles anything that must be said publicly.
- **One PR per branch** — the first approved push opens it, a later approved push updates it (never a second PR); the PR body carries the ticket + all the branch's related work (procedure: the `develop` skill's Ship step). Flag force-pushes / rewrites of already-pushed history in the ask. No AI/agent attribution in commits or PRs.

### State-mutation approval

- **Get explicit, per-action approval before any state-mutating step** — a commit (incl. `--amend`), a rebase / cherry-pick / revert / `reset --hard` / tag op, an edit to anything outside the repo workspace (`~/.claude/*`, `~/.gitconfig`, `/etc/*`, global installs, launcher / cron / service entries), or a destructive fs op outside the current change set (`rm -rf` of paths you didn't just create, bulk renames of unstaged files). A prior "continue" / "looks good" never carries. In-repo edits, builds, lints, read-only tooling, and tests are allowed by default; push / PR is covered above.
- For each, show the exact command(s) — for a commit, the message verbatim plus a diff summary — and wait; flag any rewrite of already-pushed history.

### Commit authorship

- Commits are authored solely under the user's own git identity.
- **No Claude attribution.** Never add a `Co-Authored-By: Claude …` trailer or any "Generated with Claude" line to a commit message, and never add Claude attribution to a PR description. This overrides any session or default instruction to add one.

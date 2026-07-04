# agent-toolkit

My portable agent tool set in two tiers: the **always-on principles** I work by ([`core.md`](core.md)) and the **task-specific procedures** for speccing, planning, and development, codified as [Claude Code skills](https://docs.claude.com/en/docs/claude-code). Both apply automatically in any project.

Grown out of the [unyt workshop](https://github.com/unytco) — the workshop's `documentation/DEVELOPMENT_WORKFLOW.md` + `SPEC_DISCIPLINE.md` are the reference implementation of these patterns; the skills here are their project-independent form.

## Core vs. skills

Two tiers, matching how Claude Code loads them:

- **[`core.md`](core.md) — always-on principles.** Imported by this repo's [`CLAUDE.md`](CLAUDE.md), so it's in context every session and every task: how to work (simple-but-finished, production focus, reuse, verify against reality, sweep on rename, one-home) and the git guardrails (publishing — push / PR / public comment — gated on a shown plan + explicit go-ahead; never post as the user; no AI attribution). Small and stable — principles, not procedures — so they apply during a chore or a one-line edit just as much as a feature.
- **[`skills/`](skills/) — on-demand procedures and reference.** Each a self-describing `SKILL.md` whose `description` frontmatter is the auto-trigger; the body loads only when it's relevant. **The skills are their own catalog** — the tree under [`skills/`](skills/) is the list (the snippet below prints it), adding one needs no edit here. They cover:
  - **Development flow** — spec → plan → develop (build → test → self-review loop → ship), mapped to skills and postures by `caps`; each phase skill fires on its own mid-flow.
  - **Work tracking** — chosen by what the work *is*: a **feature** (the workflow above), a **chore** (a maintenance execution doc), a **backlog** item (the unscheduled queue).
  - **Review loops** — iterative rounds until one comes back clean: one for documents/plans, one for UI development (screenshot galleries of the real app).
  - **Writing style** — how code comments, markdown, and changelogs should read; applied by type whenever you write or edit them.
  - **Setup** — scaffold a new repo with the standard contract.

Print the live skill list with descriptions straight from the frontmatter — never a hand-kept table:

```bash
for f in $(find skills -name SKILL.md | sort); do
  awk '/^name:/{sub(/^name: */,"");n=$0} /^description:/{sub(/^description: */,"");print "- "n": "$0; exit}' "$f"
done
```

## Install (per machine)

One command, idempotent, self-repairing:

```bash
git clone git@github.com:zo-el/agent-toolkit.git && cd agent-toolkit
./install.sh        # preview every change first with: ./install.sh --dry-run
```

[`install.sh`](install.sh) wires everything through the **stable path `~/.claude/agent-toolkit`** — a symlink it owns — so device config never embeds a checkout path: move the repo, re-run `./install.sh` from the new location, and only the symlink changes. It:

- symlinks every skill into `~/.claude/skills` ([`install-skills.sh`](install-skills.sh), also re-runnable on its own);
- points `statusLine` and all hooks in `~/.claude/settings.json` at [`hooks/`](hooks/) — a jq merge that replaces toolkit-managed entries, preserves everything else, and backs the original up to `~/.claude/backups/` first;
- writes the one-line device pointer `~/.claude/CLAUDE.md` → the toolkit's [`CLAUDE.md`](CLAUDE.md) (whose import chain pulls in `core.md`);
- runs a doctor: every wired path must exist and be executable.

**It never goes stale by itself.** `SessionStart` re-runs `install.sh --sync` (symlink + skills + doctor) at every session start — new skills pulled from another machine are live by the next session, and a broken install prints its diagnosis into the session context, where the agent will see and surface it. A `PostToolUse` hook re-syncs the moment a skill file is edited ([`hooks/sync-on-skill-edit.sh`](hooks/sync-on-skill-edit.sh), path-gated so unrelated edits don't trigger it).

Provision the `skill-creator` plugin once (the skill-authoring skill uses it to test/tune skills):

```bash
command -v claude >/dev/null && claude plugin install skill-creator@claude-plugins-official --scope user
```

## Enforcement — guardrails as hooks, not prose

`core.md`'s gates are enforced mechanically, so they hold even in auto-accept permission modes; [`tests/run.sh`](tests/run.sh) is the regression suite:

- [`hooks/guard-git.sh`](hooks/guard-git.sh) (PreToolUse · Bash) — **denies** public words under the user's identity (`gh pr/issue comment`, `gh pr review`, mutating comment/review API calls) and **forces an approval prompt** for publishing (`git push`, `gh pr create/merge/…`, package publish) and state mutation (commits, history rewrites, `reset --hard`, recursive `rm` outside the workspace, shell writes into `~/.claude`, global installs, `sudo`, cron/service edits).
- [`hooks/guard-config.sh`](hooks/guard-config.sh) (PreToolUse · Write/Edit) — approval prompt for device config (`~/.claude/*`, `~/.gitconfig`, `/etc/*`) and for the guard hooks themselves. Claude's own memory (`~/.claude/projects/**`), backups, and paths that resolve into a repo workspace stay open; paths are realpath-resolved so a symlink can't dodge the gate in either direction.
- [`hooks/format-on-edit.sh`](hooks/format-on-edit.sh) (PostToolUse, async) — auto-formats every file as it's written: rustfmt always, prettier only where the project carries a prettier config, black when installed.

Layering, honestly: these hooks are the *policy* layer and fail open if `jq` is missing (the doctor flags that). For a hard wall beneath them, enable Claude Code's native OS sandbox (`/sandbox`, bubblewrap) — it blocks stray writes at the kernel level, including to `settings.json` itself.

## Statusline

[`hooks/statusline.py`](hooks/statusline.py) (python3, stdlib-only — no npm/node at render time) shows, at all times: active cap chip · model (+`1M` context marker) · reasoning effort · context bar and % · session cost and lines changed · rate-limit usage · git branch+dirty · directory. It reads the native statusline JSON fields first (`effort.level`, `context_window.*`, Claude Code ≥ 2.1.119) and falls back to transcript + settings scanning on older versions; every segment fails silent — the line itself never breaks.

## Layout & lifecycle

- Always-on principles live in [`core.md`](core.md) (imported by [`CLAUDE.md`](CLAUDE.md)); each task procedure is one directory under [`skills/`](skills/) with a single `SKILL.md` (frontmatter `name` + `description` — the description is the auto-trigger).
- Home: [`zo-el/agent-toolkit`](https://github.com/zo-el/agent-toolkit), a standalone repo — it serves the whole ecosystem, not any one project. The checkout can live at any path (currently `git_repo/personal/agent-toolkit`); device config reaches it only through the `~/.claude/agent-toolkit` symlink, so moving it again is a one-command repair (`./install.sh`). Deliberately not a submodule of anything: consumers are the `~/.claude` symlinks, not any project's build, so a pin would only drift.
- Division of labor: [`CLAUDE.md`](CLAUDE.md) (imported by a one-line device pointer at `~/.claude/CLAUDE.md`) describes the toolkit and imports [`core.md`](core.md); **`core.md`** holds the always-on principles (including the never-push / no-attribution guardrails); **the skills** hold task procedures; **per-project docs** (written by `project-bootstrap`) hold each repo's visible contract. A session learning is codified into `core.md` (a principle) or a skill (a procedure), never duplicated into device config or repos.
- Future: package as a Claude Code plugin if the set ever needs versioned distribution beyond symlinks.

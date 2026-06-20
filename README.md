# agent-toolkit

My portable agent tool set in two tiers: the **always-on principles** I work by ([`core.md`](core.md)) and the **task-specific procedures** for speccing, planning, and development, codified as [Claude Code skills](https://docs.claude.com/en/docs/claude-code). Both apply automatically in any project.

Grown out of the [unyt workshop](https://github.com/unytco) — the workshop's `documentation/DEVELOPMENT_WORKFLOW.md` + `SPEC_DISCIPLINE.md` are the reference implementation of these patterns; the skills here are their project-independent form.

## Core vs. skills

Two tiers, matching how Claude Code loads them:

- **[`core.md`](core.md) — always-on principles.** Imported by this repo's [`CLAUDE.md`](CLAUDE.md), so it's in context every session and every task: how to work (simple-but-finished, production focus, reuse, verify against reality, sweep on rename, one-home) and the git guardrails (never push, no AI attribution). Small and stable — principles, not procedures — so they apply during a chore or a one-line edit just as much as a feature.
- **[`skills/`](skills/) — on-demand procedures and reference.** Each a self-describing `SKILL.md` whose `description` frontmatter is the auto-trigger; the body loads only when it's relevant. **The skills are their own catalog** — [`ls skills/`](skills/) is the list, adding one needs no edit here. They cover:
  - **Feature workflow** — `software-development` owns spec → plan → develop → finalize, delegating each phase to its own skill; every phase skill also fires on its own mid-flow.
  - **Work tracking** — chosen by what the work *is*: a **feature** (the workflow above), a **chore** (a maintenance execution doc), a **backlog** item (the unscheduled queue).
  - **Review loops** — iterative rounds until one comes back clean: one for documents/plans, one for UI development (screenshot galleries of the real app).
  - **Writing style** — how code comments, markdown, and changelogs should read; applied by type whenever you write or edit them.
  - **Setup** — scaffold a new repo with the standard contract.

Print the live skill list with descriptions straight from the frontmatter — never a hand-kept table:

```bash
for f in skills/*/SKILL.md; do
  awk '/^name:/{sub(/^name: */,"");n=$0} /^description:/{sub(/^description: */,"");print "- "n": "$0; exit}' "$f"
done
```

## Install (per machine)

Symlink each skill so Claude Code discovers them, and point the device's global `CLAUDE.md` at the toolkit — that import chain pulls in `core.md` automatically, so the always-on principles need no symlink:

```bash
# symlink every skill — re-run any time to pick up new or renamed ones
for d in "$(pwd)"/skills/*/; do
  ln -sfn "$d" ~/.claude/skills/"$(basename "$d")"
done
# drop symlinks whose target was removed (e.g. after a merge or rename)
find ~/.claude/skills -maxdepth 1 -type l ! -exec test -e {} \; -delete

cat > ~/.claude/CLAUDE.md <<DONE
# Global instructions

All always-apply rules live in the portable agent-toolkit (its own git repo) — this file is only this device's pointer to it. New rules and learnings go INTO the toolkit, never here.

@$(pwd)/CLAUDE.md
DONE
```

## Layout & lifecycle

- Always-on principles live in [`core.md`](core.md) (imported by [`CLAUDE.md`](CLAUDE.md)); each task procedure is one directory under [`skills/`](skills/) with a single `SKILL.md` (frontmatter `name` + `description` — the description is the auto-trigger).
- Home: [`zo-el/agent-toolkit`](https://github.com/zo-el/agent-toolkit). The working checkout lives inside the workshop as an **untracked sibling** (workshop `.gitignore`) so it's visible in one IDE — deliberately not a submodule: consumers are the `~/.claude/skills` symlinks, not any project's build, so a pin would only drift.
- Division of labor: [`CLAUDE.md`](CLAUDE.md) (imported by a one-line device pointer at `~/.claude/CLAUDE.md`) describes the toolkit and imports [`core.md`](core.md); **`core.md`** holds the always-on principles (including the never-push / no-attribution guardrails); **the skills** hold task procedures; **per-project docs** (written by `project-bootstrap`) hold each repo's visible contract. A session learning is codified into `core.md` (a principle) or a skill (a procedure), never duplicated into device config or repos.
- Future: package as a Claude Code plugin if the set ever needs versioned distribution beyond symlinks.

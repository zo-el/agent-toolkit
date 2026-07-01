# agent-toolkit

My portable agent tool set in two tiers: the **always-on principles** I work by ([`core.md`](core.md)) and the **task-specific procedures** for speccing, planning, and development, codified as [Claude Code skills](https://docs.claude.com/en/docs/claude-code). Both apply automatically in any project.

Grown out of the [unyt workshop](https://github.com/unytco) — the workshop's `documentation/DEVELOPMENT_WORKFLOW.md` + `SPEC_DISCIPLINE.md` are the reference implementation of these patterns; the skills here are their project-independent form.

## Core vs. skills

Two tiers, matching how Claude Code loads them:

- **[`core.md`](core.md) — always-on principles.** Imported by this repo's [`CLAUDE.md`](CLAUDE.md), so it's in context every session and every task: how to work (simple-but-finished, production focus, reuse, verify against reality, sweep on rename, one-home) and the git guardrails (push/PR only with per-action approval, no AI attribution). Small and stable — principles, not procedures — so they apply during a chore or a one-line edit just as much as a feature.
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

Symlink each skill so Claude Code discovers them, point the device's global `CLAUDE.md` at the toolkit (that import chain pulls in `core.md`, so the always-on principles need no symlink), provision the `skill-creator` plugin, and register the auto-sync hooks (below) so the install never drifts:

```bash
# symlink every skill into ~/.claude/skills (idempotent — re-run any time)
./install-skills.sh

# provision the skill-creator plugin (the skill-authoring skill uses it to test/tune skills)
command -v claude >/dev/null && claude plugin install skill-creator@claude-plugins-official --scope user

cat > ~/.claude/CLAUDE.md <<DONE
# Global instructions

All always-apply rules live in the portable agent-toolkit (its own git repo) — this file is only this device's pointer to it. New rules and learnings go INTO the toolkit, never here.

@$(pwd)/CLAUDE.md
DONE
```

**Stay synced automatically.** [`install-skills.sh`](install-skills.sh) is idempotent — wire it into Claude Code hooks in `~/.claude/settings.json` so the install can never go stale: `SessionStart` re-syncs at the start of every session (picking up skills added, renamed, or removed — even by a `git pull` on another machine), and `PostToolUse` re-syncs after an edit so a mid-session skill add registers immediately. Point both at this checkout's absolute path to the script:

```json
"hooks": {
  "SessionStart": [
    { "matcher": "startup|resume|clear",
      "hooks": [ { "type": "command", "command": "/abs/path/to/agent-toolkit/install-skills.sh > /dev/null 2>&1 || true" } ] }
  ],
  "PostToolUse": [
    { "matcher": "Write|Edit",
      "hooks": [ { "type": "command", "command": "/abs/path/to/agent-toolkit/install-skills.sh > /dev/null 2>&1 || true" } ] }
  ]
}
```

## Layout & lifecycle

- Always-on principles live in [`core.md`](core.md) (imported by [`CLAUDE.md`](CLAUDE.md)); each task procedure is one directory under [`skills/`](skills/) with a single `SKILL.md` (frontmatter `name` + `description` — the description is the auto-trigger).
- Home: [`zo-el/agent-toolkit`](https://github.com/zo-el/agent-toolkit). The working checkout lives inside the workshop as an **untracked sibling** (workshop `.gitignore`) so it's visible in one IDE — deliberately not a submodule: consumers are the `~/.claude/skills` symlinks, not any project's build, so a pin would only drift.
- Division of labor: [`CLAUDE.md`](CLAUDE.md) (imported by a one-line device pointer at `~/.claude/CLAUDE.md`) describes the toolkit and imports [`core.md`](core.md); **`core.md`** holds the always-on principles (including the never-push / no-attribution guardrails); **the skills** hold task procedures; **per-project docs** (written by `project-bootstrap`) hold each repo's visible contract. A session learning is codified into `core.md` (a principle) or a skill (a procedure), never duplicated into device config or repos.
- Future: package as a Claude Code plugin if the set ever needs versioned distribution beyond symlinks.

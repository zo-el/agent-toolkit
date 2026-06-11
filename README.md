# agent-toolkit

My portable agent tool set: the speccing, planning, development, and documentation patterns I work by, codified as [Claude Code skills](https://docs.claude.com/en/docs/claude-code) so they apply automatically in any project.

Grown out of the [unyt workshop](https://github.com/unytco) — the workshop's `documentation/DEVELOPMENT_WORKFLOW.md` + `SPEC_DISCIPLINE.md` are the reference implementation of these patterns; the skills here are their project-independent form.

## Skills

| Skill                                                | Phase / concern   | Fires when…                                      |
| ---------------------------------------------------- | ----------------- | ------------------------------------------------ |
| [feature-spec](skills/feature-spec/)                 | Phase 1 — spec    | a feature is described, scoped, or re-specced    |
| [feature-milestones](skills/feature-milestones/)     | Phase 2 — plan    | a spec is ready to break into milestones         |
| [feature-develop](skills/feature-develop/)           | Phase 3–4 — build | a milestone is ready to implement                |
| [doc-style](skills/doc-style/)                       | cross-cutting     | any markdown is written or substantially edited  |
| [plannotator-loop](skills/plannotator-loop/)         | review            | a plan/spec/milestone needs back-and-forth review |
| [project-bootstrap](skills/project-bootstrap/)       | new project       | a fresh repo needs the standard contract         |

## Install (per machine)

Symlink each skill into the personal skills directory so Claude Code discovers them in every project:

```bash
for s in feature-spec feature-milestones feature-develop doc-style plannotator-loop project-bootstrap; do
  ln -sfn "$(pwd)/skills/$s" ~/.claude/skills/$s
done
```

## Layout & lifecycle

- One directory per skill under [`skills/`](skills/), each a single `SKILL.md` (frontmatter `name` + `description` — the description is the auto-trigger).
- This repo lives inside the workshop checkout as an **untracked sibling** (workshop `.gitignore`) so it's visible in one IDE, but has its own git history — push it to GitHub whenever.
- Division of labor: **global `~/.claude/CLAUDE.md`** holds always-on hard constraints (git rules), **these skills** hold procedures, **per-project docs** (written by `project-bootstrap`) hold each repo's visible contract.
- Future: package as a Claude Code plugin if the set ever needs versioned distribution beyond symlinks.

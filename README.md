# agent-toolkit

My portable agent tool set: the speccing, planning, development, and documentation patterns I work by, codified as [Claude Code skills](https://docs.claude.com/en/docs/claude-code) so they apply automatically in any project.

Grown out of the [unyt workshop](https://github.com/unytco) — the workshop's `documentation/DEVELOPMENT_WORKFLOW.md` + `SPEC_DISCIPLINE.md` are the reference implementation of these patterns; the skills here are their project-independent form.

## Skills

| Skill                                                | Phase / concern   | Fires when…                                                                          |
| ---------------------------------------------------- | ----------------- | ------------------------------------------------------------------------------------ |
| [software-development](skills/software-development/) | the whole flow    | any feature work starts — owns phase sequence + gates, delegates to the phase skills |
| [feature-spec](skills/feature-spec/)                 | Phase 1 — spec    | a feature is described, scoped, or re-specced                                        |
| [feature-milestones](skills/feature-milestones/)     | Phase 2 — plan    | a spec is ready to break into milestones                                             |
| [feature-develop](skills/feature-develop/)           | Phase 3–4 — build | a milestone is ready to implement                                                    |
| [code-style](skills/code-style/)                     | cross-cutting     | code is written or substantially edited                                              |
| [doc-style](skills/doc-style/)                       | cross-cutting     | any markdown is written or substantially edited                                      |
| [git](skills/git/)                                   | guardrail         | before any git / gh operation — never push, no Claude attribution                    |
| [backlog](skills/backlog/)                           | cross-cutting     | filing follow-ups, "what's next", or a sweep is due                                  |
| [plannotator-loop](skills/plannotator-loop/)         | review            | a plan/spec/milestone needs back-and-forth review                                    |
| [ui-review-loop](skills/ui-review-loop/)             | cross-cutting     | UI is built or changed — screenshot-gallery review rounds                            |
| [project-bootstrap](skills/project-bootstrap/)       | new project       | a fresh repo needs the standard contract                                             |

## Install (per machine)

Symlink each skill into the personal skills directory so Claude Code discovers them in every project, and point the device's global memory at the toolkit's always-on rules:

```bash
for s in software-development feature-spec feature-milestones feature-develop code-style doc-style git backlog plannotator-loop project-bootstrap ui-review-loop; do
  ln -sfn "$(pwd)/skills/$s" ~/.claude/skills/$s
done

cat > ~/.claude/CLAUDE.md <<DONE
# Global instructions

All always-apply rules live in the portable agent-toolkit (its own git repo) — this file is only this device's pointer to it. New rules and learnings go INTO the toolkit, never here.

@$(pwd)/CLAUDE.md
DONE
```

## Layout & lifecycle

- One directory per skill under [`skills/`](skills/), each a single `SKILL.md` (frontmatter `name` + `description` — the description is the auto-trigger).
- Home: [`zo-el/agent-toolkit`](https://github.com/zo-el/agent-toolkit). The working checkout lives inside the workshop as an **untracked sibling** (workshop `.gitignore`) so it's visible in one IDE — deliberately not a submodule: consumers are the `~/.claude/skills` symlinks, not any project's build, so a pin would only drift.
- Division of labor: [`CLAUDE.md`](CLAUDE.md) (here, imported by a one-line device pointer at `~/.claude/CLAUDE.md`) describes the toolkit and how it grows — it holds no rules of its own; **these skills** hold every rule and procedure (the [`git`](skills/git/) skill owns the never-push / no-attribution guardrails); **per-project docs** (written by `project-bootstrap`) hold each repo's visible contract. Session learnings are codified into a skill, never duplicated into device config or repos.
- Future: package as a Claude Code plugin if the set ever needs versioned distribution beyond symlinks.

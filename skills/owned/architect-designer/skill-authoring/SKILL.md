---
name: skill-authoring
description: How to write a Claude Code skill (SKILL.md) so it auto-triggers reliably — description format, structure, and this toolkit's house conventions, plus when to reach for skill-creator. Use whenever creating, editing, reviewing, or renaming a skill / SKILL.md, or codifying a session learning into a skill.
---

# Skill authoring

How skills are written in this toolkit. The spec/mechanics are Anthropic's, the tool is `skill-creator`, and this holds the house conventions and points at both. Markdown formatting follows the `documentation-style` skill. Two placement decisions come first: **core-vs-skill** (toolkit-root `CLAUDE.md`) and, for a skill, **which cap owns it** (below).

## The description is the auto-trigger — get it right

A skill's `name` + `description` are the only parts always in context; Claude matches the conversation against them to decide whether to load the body. So the description must say **when to fire**, in the words and activities that signal it.

- **Format:** `[what it does]. Use when [trigger situations / keywords / the activity happening].` Third person, key trigger first, ≤1024 chars.
- **Include the real cues** — the file types, verbs, and domain terms a user would actually say or be doing. Vague or what-only descriptions are the #1 reason a skill silently fails to fire.
- **The name is half the signal** — descriptive, lowercase-hyphen, and distinct from siblings (a near-twin name blurs matching).
- **Mutually distinct** — two skills shouldn't fire ambiguously on the same cue; sharpen each so the right one wins.

## Structure

- **Lean body** — keep it short (well under Anthropic's 500-line cap; ours run ~30–50). Decisions, not explanations (per `documentation-style`). Assume Claude is smart — every token earns its place.
- **Progressive disclosure** — push long reference into sibling files the skill links to (one level deep); they load only when referenced, so the always-on trigger metadata stays cheap.
- **One home** — never restate what `core.md` or another skill owns; lean on its auto-fire instead (a skill needing general doc/code style relies on `documentation-style`).

## Placement — which cap owns it

Skills live in a tree **by owning cap**; the path is the only home for ownership, so names stay semantic (never prefix with a cap). Decide before writing:

- **A new cap** (a working posture / soul file) → `skills/caps/cap-<role>/`, following the soul-file shape — *Who you are · What you use · Boundaries · Hand-off · Grow & learn* (see `caps`). Rare.
- **Owned by exactly one cap** (only that cap would ever use it) → `skills/owned/<cap>/`. The owning cap's soul file points to it under *What you use → Yours*.
- **Cross-cutting** (more than one cap uses it) → `skills/cross-cutting/`, listed once in `caps`.

Name the cap(s) it *could* apply to: exactly one → owned; more than one → cross-cutting (don't force it under a single cap). When unsure, default to cross-cutting and let a cap claim it later — re-owning is just a `mv`. If the skill is a cap's *exclusive* tool boundary (e.g. only the PM touches Linear), declare it in the cap's soul file and hard-enforce with a `PreToolUse` hook — a skill alone can't lock a tool.

## Test it with skill-creator

`skill-creator` (Anthropic's official, community-standard tool) is how to verify and tune triggering — don't eyeball it:

- `/skill-creator` → `eval` checks the skill fires on the prompts it should; `improve` A/B-tunes the description for trigger accuracy.
- It's provisioned by the toolkit install; to add it by hand: `claude plugin install skill-creator@claude-plugins-official`.
- Spec + mechanics: [Anthropic skill-authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices).

## Lifecycle

The `skills/` tree **is** the catalog — self-describing via frontmatter, no hand-maintained index. Install is discovery-driven: `install-skills.sh` symlinks every directory containing a `SKILL.md` at **any depth** (grouping folders like `caps/` `owned/` `cross-cutting/` carry none) and prunes broken links, so adding a skill in any group folder needs no edit elsewhere. Basenames stay unique across the tree.

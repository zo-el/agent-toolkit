---
name: skill-authoring
description: How to write a Claude Code skill (SKILL.md) so it auto-triggers reliably — description format, structure, and this toolkit's house conventions, plus when to reach for skill-creator. Use whenever creating, editing, reviewing, or renaming a skill / SKILL.md, or codifying a session learning into a skill.
---

# Skill authoring

How skills are written in this toolkit. The spec/mechanics are Anthropic's, the tool is `skill-creator`, and this holds the house conventions and points at both. Markdown formatting follows the `documentation-style` skill; the **core-vs-skill placement** decision lives in [`CLAUDE.md`](../../CLAUDE.md) — decide that first.

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

## Test it with skill-creator

`skill-creator` (Anthropic's official, community-standard tool) is how to verify and tune triggering — don't eyeball it:

- `/skill-creator` → `eval` checks the skill fires on the prompts it should; `improve` A/B-tunes the description for trigger accuracy.
- It's provisioned by the toolkit install; to add it by hand: `claude plugin install skill-creator@claude-plugins-official`.
- Spec + mechanics: [Anthropic skill-authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices).

## Lifecycle

The `skills/` directory **is** the catalog — self-describing via frontmatter, no hand-maintained index. Install is directory-driven (symlink every `skills/*/`, prune broken links), so adding a skill needs no edit elsewhere.

# Agent toolkit

Portable instructions for this user, in two tiers: **always-on principles** in [`core.md`](core.md) (imported below, so it loads every session and applies to every task) and **task procedures and detailed reference** as skills under [`skills/`](skills/) (each loads only when it's relevant). The device's `~/.claude/CLAUDE.md` imports this file; the toolkit is a git repo that travels across machines, so nothing here depends on device config.

@core.md

Where a session learning goes: **`core.md` stays small and stable** — only short, always-true principles and guardrails that apply to *every* task. Anything detailed, domain-specific, or a growing reference (even cross-cutting, like writing style) is a **skill** with an auto-trigger `description`, not core — a well-described skill fires whenever it's relevant, so it applies everywhere without bloating always-on context. Grow an existing skill, or add a new one only for a genuinely new task — don't split too fine. One home per rule — never duplicate into device-local config (`~/.claude/*`) or per-repo docs. Propose the addition to the user — their toolkit, their call — write it once approved, and remind them to commit/push the toolkit so the learning isn't lost.

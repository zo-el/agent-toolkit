# agent-toolkit

My portable agent tool set in three tiers: the **always-on principles** I work by ([`core.md`](core.md)), the **role agents** the session orchestrates ([`agents/`](agents/)), and the **task-specific procedures** they follow, codified as [Claude Code skills](https://docs.claude.com/en/docs/claude-code). All apply automatically in any project.

Grown out of the [unyt workshop](https://github.com/unytco) — the workshop's `documentation/DEVELOPMENT_WORKFLOW.md` + `SPEC_DISCIPLINE.md` are the reference implementation of these patterns; the skills here are their project-independent form.

## The model — one orchestrator, role agents

The session itself is the **pure orchestrator** (`core.md`): it thinks, decomposes work, delegates every piece of execution to the role agents, verifies and consolidates what they return, and is the only one that talks to the user or publishes — it never does the execution work itself. Each agent runs in its own isolated context, with a `tools:` allowlist as its outer limit and its definition as the role it keeps inside that limit:

| Agent | Runs | Tools it does **not** have | Role discipline |
| --- | --- | --- | --- |
| 🏛 [`architect-designer`](agents/architect-designer.md) | `feature-spec` → `feature-tasks` (spec + task catalog + AC, owns coverage) | no Linear | writes docs + tasks, never application source |
| 📋 [`project-manager`](agents/project-manager.md) | `linear-sync` · `next-up` · `backlog` (track, organize, surface) | no Agent (**the only agent with Linear**) | tracks; never authors tasks/AC or builds |
| 🔨 [`developer`](agents/developer.md) | `develop` · `ui-development` (build → test → self-review loop, ship-ready) | no Linear | full edit; never pushes or posts |
| 🔍 [`reviewer`](agents/reviewer.md) | `/code-review` · `/security-review` on demand (independent scrutiny) | **no Write/Edit**, no Linear | reports ranked findings; never patches |
| 🔬 [`researcher`](agents/researcher.md) | `deep-research` (web/external questions, cited answers) | **no Write/Edit**, no Linear | answers with citations; no repo changes |

Honest about the layering: the allowlist is the hard boundary (the reviewer genuinely *cannot* call Edit; only the PM *has* Linear tools), while "never writes source", "never pushes" are role discipline in each definition — backed by the guard hooks, which fire inside subagents too. Agents that need `Bash` to do their job (build, test, reproduce a finding) could in principle write through it; the gates above are what make that a violation rather than an accident.

**The roles orchestrate too, one level down.** Work that splits into independent parts defaults to one agent per part, and every role but the PM carries `Agent` so it can fan out *within its own role* — sub-developers on independent parts of a fix, one reviewer per lens, parallel research angles — converging the results itself. The cap is **two levels**: the session spawns agents, those agents may spawn agents, and there it stops (`/code-review`, which fans out internally, is exempt). The PM is deliberately without `Agent` — parallel board writes are how a board drifts.

The built-ins (`Explore`, `Plan`, `general-purpose`) cover generic search/planning — the custom roles exist for the skills and boundaries above, and every agent cleans up its own processes ([`hooks/spawn-managed.sh`](hooks/spawn-managed.sh) + [`hooks/reap-managed.sh`](hooks/reap-managed.sh) guarantee it). The full playbook — when to delegate, briefs, the Agent Teams task board, worktree isolation — is the `orchestrating-subagents` skill.

## Core vs. skills

- **[`core.md`](core.md) — always-on principles.** Imported by this repo's [`CLAUDE.md`](CLAUDE.md), so it's in context every session and every task: the orchestrator stance, how to work (simple-but-finished, production focus, reuse, verify against reality, sweep on rename, one-home) and the git guardrails (publishing — push / PR / public comment — gated on a shown plan + explicit go-ahead; never post as the user; no AI attribution). Small and stable — principles, not procedures.
- **[`skills/`](skills/) — on-demand procedures and reference.** Each a self-describing `SKILL.md` whose `description` frontmatter is the auto-trigger; the body loads only when it's relevant. **The skills are their own catalog** — the tree under [`skills/`](skills/) is the list (the snippet below prints it), adding one needs no edit here. They cover:
  - **Development flow** — spec → plan → develop (build → test → self-review loop → ship), mapped to agents and skills by `orchestrating-subagents`; each phase skill fires on its own mid-flow.
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
- **copies** every agent into `~/.claude/agents/` (copied, not symlinked — the agents file-watcher doesn't reliably follow symlinks; a manifest prunes renamed/removed ones without touching your own agents);
- points `statusLine` and all hooks in `~/.claude/settings.json` at [`hooks/`](hooks/) — a jq merge that replaces toolkit-managed entries, preserves everything else, and backs the original up to `~/.claude/backups/` first — and sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (the shared task list / teammate coordination layer the orchestrator uses);
- writes the one-line device pointer `~/.claude/CLAUDE.md` → the toolkit's [`CLAUDE.md`](CLAUDE.md) (whose import chain pulls in `core.md`);
- stamps the installed version (`~/.claude/agent-toolkit-version`, from the toolkit's git) so the statusline can show it and flag drift;
- runs a doctor: every wired path must exist and be executable, agents fully copied.

**It never goes stale by itself.** `SessionStart` re-runs `install.sh --sync` (symlink + skills + doctor) at every session start — new skills pulled from another machine are live by the next session, and a broken install prints its diagnosis into the session context, where the agent will see and surface it. A `PostToolUse` hook re-syncs the moment a skill file is edited ([`hooks/sync-on-skill-edit.sh`](hooks/sync-on-skill-edit.sh), path-gated so unrelated edits don't trigger it).

Provision the `skill-creator` plugin once (the skill-authoring skill uses it to test/tune skills):

```bash
command -v claude >/dev/null && claude plugin install skill-creator@claude-plugins-official --scope user
```

## Enforcement — guardrails as hooks, not prose

`core.md`'s gates are enforced mechanically, so they hold even in auto-accept permission modes; [`tests/run.sh`](tests/run.sh) is the regression suite:

- [`hooks/guard-git.sh`](hooks/guard-git.sh) (PreToolUse · Bash) — **denies** public words under the user's identity (`gh pr/issue comment`, `gh pr review`, mutating comment/review API calls) and **forces an approval prompt** for publishing (`git push`, `gh pr create/merge/…`, package publish) and destructive or device state (`reset --hard` / `clean -f` / `filter-branch`, recursive `rm` outside the workspace, shell writes into `~/.claude`, global installs, `sudo`, cron/service edits) — while local git workflow (commits, branches, rebases, tags) stays free: the push ask is the review point.
- [`hooks/guard-config.sh`](hooks/guard-config.sh) (PreToolUse · Write/Edit) — approval prompt for device config (`~/.claude/*`, `~/.gitconfig`, `/etc/*`) and for the guard hooks themselves. Claude's own memory (`~/.claude/projects/**`), backups, and paths that resolve into a repo workspace stay open; paths are realpath-resolved so a symlink can't dodge the gate in either direction.
- [`hooks/format-on-edit.sh`](hooks/format-on-edit.sh) (PostToolUse, async) — auto-formats every file as it's written: rustfmt always, prettier only where the project carries a prettier config, black when installed.
- [`hooks/spawn-managed.sh`](hooks/spawn-managed.sh) + [`hooks/reap-managed.sh`](hooks/reap-managed.sh) (SessionEnd / SessionStart / SubagentStop) — **nothing registered outlives the session that started it.** Long-lived processes are registered at spawn against their owning CLI process (pid + kernel start time, so `/clear` and `/resume` can't orphan the record). Two triggers, because neither alone suffices: **SessionEnd** reaps the ending session's own processes (it passes its `session_id`, since at that moment the CLI is still alive by construction), and **SessionStart** catches whatever a crashed or `kill -9`'d session left behind (its pid is gone). TERM first, KILL only after a grace window. Everything it can't verify fails safe — unknown owner, an unreadable or missing start time, no `jq` — it would rather leak a process than kill live work. Scope, honestly: a subagent shares its parent's CLI process, so this does **not** clean up after an individual agent mid-session — that stays each agent's own duty, which is why every definition carries it. Without any of this, a raw `nohup … &` simply reparents to init and lives forever (verified).
- These guard hooks fire **inside subagents too**, so an agent's stray `git push` still hits the approval gate — belt-and-suspenders with each agent's `tools:` allowlist.

The installer also sets `permissions.defaultMode: "auto"`, so Claude judges routine commands itself instead of prompting for each — that is what lets a background agent finish unattended, and it means no hand-maintained list of build/test commands to keep current. The hooks above fire *independently of permission mode*, so every gate they own still prompts. The honest trade: in-workspace destructive commands (`rm -rf ./build`) no longer stop for a prompt — out-of-workspace ones still do, and git is the net for anything in the repo.

Layering, honestly: these hooks are the *policy* layer and fail open if `jq` is missing (the doctor flags that). For a hard wall beneath them, enable Claude Code's native OS sandbox (`/sandbox`, bubblewrap) — it blocks stray writes at the kernel level, including to `settings.json` itself. Worth knowing before you do: it also confines what Claude's own commands can reach (writes outside cwd, network beyond an allowlist), which can break agent work that needs a local service.

## Statusline

[`hooks/statusline.py`](hooks/statusline.py) (python3, stdlib-only — no npm/node at render time) shows, at all times: model (+`1M` context marker) · reasoning effort · context bar and % · session cost and lines changed · rate-limit usage · git branch+dirty · directory · **toolkit version + freshness**. It reads the native statusline JSON fields first (`effort.level`, `context_window.*`, Claude Code ≥ 2.1.119) and falls back to transcript + settings scanning on older versions; every segment fails silent — the line itself never breaks.

The version segment (`⬡ v<count>·<sha>`) is your "are my changes applied?" light. `install.sh` stamps it at each full install from the toolkit's own git (`git rev-list --count` + short SHA — auto, no manual bumping); the statusline reads that stamp and appends a `⚠` when the repo's HEAD has since moved past it — i.e. you committed and haven't re-run `./install.sh`. (Skills and `core.md` are live through the symlink regardless; the `⚠` nudges re-applying the *copied* pieces — agents and `settings.json`.)

## Notifications

[`hooks/notify.sh`](hooks/notify.sh) plays a sound **only when it's your turn** — so you can keep your eyes off the screen until you're actually needed:

- **`Notification` → `alert`** (a distinct, attention-grabbing sound): Claude needs a permission or is asking a question.
- **`Stop` → `done`** (a softer completion sound): the main agent finished its turn and the reply is ready.
- **`SubagentStop` is deliberately *not* wired** — a background agent finishing is not your cue to look, so it stays silent.

The kind is passed as an argument (`notify.sh alert` / `notify.sh done`), so the hook never misreads a payload. It's cheap (a detached `paplay`/`pw-play`/`ffplay`/`aplay` of a ~20 KB sound) and fail-safe — no player or no sound file degrades to silence, never to an error. Override either cue by dropping `sounds/<kind>.<ext>` (oga/ogg/wav/mp3) in the toolkit; otherwise a distinct [freedesktop](https://www.freedesktop.org/wiki/Specifications/sound-theme-spec/) sound is used. `install.sh` wires these two events and disables the external `claude-notifications-go` plugin it replaces (so nothing plays twice).

## Layout & lifecycle

- Always-on principles live in [`core.md`](core.md) (imported by [`CLAUDE.md`](CLAUDE.md)); each role agent is one `agents/<role>.md` (frontmatter `tools`/`effort`/`skills` + a system-prompt body); each task procedure is one directory under [`skills/`](skills/) with a single `SKILL.md` (frontmatter `name` + `description` — the description is the auto-trigger).
- Home: [`zo-el/agent-toolkit`](https://github.com/zo-el/agent-toolkit), a standalone repo — it serves the whole ecosystem, not any one project. The checkout can live at any path (currently `git_repo/personal/agent-toolkit`); device config reaches it only through the `~/.claude/agent-toolkit` symlink, so moving it again is a one-command repair (`./install.sh`). Deliberately not a submodule of anything: consumers are the `~/.claude` symlinks, not any project's build, so a pin would only drift.
- Division of labor: [`CLAUDE.md`](CLAUDE.md) (imported by a one-line device pointer at `~/.claude/CLAUDE.md`) describes the toolkit and imports [`core.md`](core.md); **`core.md`** holds the always-on principles (including the never-push / no-attribution guardrails); **the skills** hold task procedures; **per-project docs** (written by `project-bootstrap`) hold each repo's visible contract. A session learning is codified into `core.md` (a principle) or a skill (a procedure), never duplicated into device config or repos.
- Future: package as a Claude Code plugin if the set ever needs versioned distribution beyond symlinks.

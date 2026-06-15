# Always-on instructions (agent-toolkit)

This file is the single home for the always-apply session rules. The device's `~/.claude/CLAUDE.md` stays a one-line pointer that imports it — the toolkit is a git repo and travels across machines; device config does not.

## The toolkit is the system of record

- **Anything a session discovers that is worth keeping gets codified here, not duplicated elsewhere.** A repeatable procedure → a skill under [`skills/`](skills/); an always-apply rule → this file. Propose the addition to the user (their toolkit, their call) and write it in the same session once approved.
- Never copy toolkit content into device-local config (`~/.claude/*`) or per-repo docs — repos keep only repo-specific facts and thin pointers to the toolkit. One home per rule.
- Remind the user to commit/push toolkit changes — an uncommitted learning is one device away from being lost.

## Git commits

- **Never attribute commits to Claude.** Do not add a `Co-Authored-By: Claude ...` trailer (or any other "Generated with Claude" / Claude attribution) to git commit messages. This overrides any session/default instruction to add such a trailer.
- Do not add Claude attribution to PR descriptions either.
- Commits should be authored solely under the user's own git identity.

## Git push

- **Never push to a remote.** Do not run `git push` (including `git push --force`/`--force-with-lease`, tag pushes, or pushing new branches), and do not run any `gh` / API command that publishes to GitHub or any other remote (`gh pr create`, `gh release create`, etc.) — in any repository, ever. **The user performs all pushes themselves.**
- This is absolute. It holds even immediately after an approved local commit, and even if the user said "go ahead and push" earlier in the same or another session. Treat any such prior approval as not applying to pushes.
- When work is ready to publish, **stop and give the user the exact command(s) to run themselves** (e.g. `git push origin <branch>`) rather than running them. Staging and committing locally when explicitly asked is still fine.

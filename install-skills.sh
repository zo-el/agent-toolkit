#!/usr/bin/env bash
# Sync this toolkit's skills into ~/.claude/skills so Claude Code discovers them.
# Idempotent — safe to re-run any time (manually, or from the SessionStart /
# PostToolUse hooks) to pick up new, renamed, or removed skills.
set -euo pipefail

# pwd -P: resolve to the real checkout even when invoked via the
# ~/.claude/agent-toolkit symlink, so skill links never route through it.
skills_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/skills" && pwd -P)"
dest="$HOME/.claude/skills"
mkdir -p "$dest"

# Symlink every skill — any dir containing a SKILL.md, at ANY depth. Skills are
# grouped into owned/ cross-cutting/ subfolders for legibility but land
# flat in ~/.claude/skills so Claude discovers them; basenames are unique across
# the tree. -sfn: replace an existing link and don't descend into a linked dir,
# so a moved/renamed skill repoints cleanly instead of nesting under the old link.
find "$skills_dir" -name SKILL.md -print0 | while IFS= read -r -d '' f; do
  d="$(dirname "$f")"
  ln -sfn "$d" "$dest/$(basename "$d")"
done

# Drop symlinks whose target is gone (a skill renamed or removed upstream).
find "$dest" -maxdepth 1 -type l ! -exec test -e {} \; -delete

echo "✓ synced $(find "$dest" -maxdepth 1 -type l | wc -l | tr -d ' ') skill symlinks into $dest"

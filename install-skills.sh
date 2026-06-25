#!/usr/bin/env bash
# Sync this toolkit's skills into ~/.claude/skills so Claude Code discovers them.
# Idempotent — safe to re-run any time (manually, or from the SessionStart /
# PostToolUse hooks) to pick up new, renamed, or removed skills.
set -euo pipefail

skills_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/skills" && pwd)"
dest="$HOME/.claude/skills"
mkdir -p "$dest"

# -sfn: replace an existing link and don't descend into a linked dir, so a
# renamed skill repoints cleanly instead of nesting under the old link.
for d in "$skills_dir"/*/; do
  ln -sfn "$d" "$dest/$(basename "$d")"
done

# Drop symlinks whose target is gone (a skill renamed or removed upstream).
find "$dest" -maxdepth 1 -type l ! -exec test -e {} \; -delete

echo "✓ synced $(find "$dest" -maxdepth 1 -type l | wc -l | tr -d ' ') skill symlinks into $dest"

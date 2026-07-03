#!/usr/bin/env python3
"""statusLine command — everything you need to know at a glance, one line:

    cap │ model │ effort │ context bar │ cost │ git branch │ dir

Reads the status JSON Claude Code pipes to stdin. Each segment is wrapped in
its own try/except and degrades to nothing — a statusline must never crash or
show a stack trace. stdlib only (python3), no jq/node dependency.

Sources, most-authoritative first:
- stdin JSON: model, cwd, session_id, transcript_path, cost totals — and any
  native effort/context fields a future Claude Code version adds (probed by
  name, used when present).
- transcript JSONL: last assistant `usage` block = live context load; the
  latest "Set effort level to X" line = session effort override. Only the tail
  (and, for effort, the head) is scanned so multi-MB transcripts stay cheap; a
  mid-file /effort change in a >3 MB transcript can be missed until the next
  change — accepted trade-off.
- ~/.claude/settings.json: persisted effortLevel default; per-session cap file
  ~/.claude/.active-cap-<session_id> written by cap-set.sh.
"""
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
DIM = "\033[2m"
RESET = "\033[0m"
BOLD = "\033[1m"
COLORS = {
    "red": "\033[31m", "green": "\033[32m", "yellow": "\033[33m",
    "blue": "\033[34m", "magenta": "\033[35m", "cyan": "\033[36m",
}
SEP = f" {DIM}│{RESET} "

TAIL_BYTES = 2 * 1024 * 1024   # transcript tail scanned for usage + effort
HEAD_BYTES = 1 * 1024 * 1024   # transcript head scanned for an early /effort

EFFORT_STYLE = {
    "max": COLORS["magenta"] + BOLD, "xhigh": COLORS["red"],
    "high": COLORS["yellow"], "medium": COLORS["cyan"], "low": DIM,
}
CAP_STYLE = {
    "cap-architect-designer": (COLORS["blue"], "🏛 Architect-Designer"),
    "cap-project-manager": (COLORS["yellow"], "📋 Project-Manager"),
    "cap-developer": (COLORS["green"], "🔨 Developer"),
    "cap-reviewer": (COLORS["red"], "🔍 Reviewer"),
    "off": (DIM, "○ cap off"),
}


def read_chunks(path):
    """(tail, head) text chunks of the transcript; head empty if file fits in tail."""
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        if size <= TAIL_BYTES:
            return f.read().decode("utf-8", "replace"), ""
        f.seek(size - TAIL_BYTES)
        tail = f.read().decode("utf-8", "replace")
        f.seek(0)
        head = f.read(HEAD_BYTES).decode("utf-8", "replace")
    return tail, head


def segment_cap(data):
    sid = data.get("session_id") or ""
    path = os.path.join(HOME, ".claude", f".active-cap-{sid}" if sid else ".active-cap")
    try:
        with open(path) as f:
            cap = f.read().strip()
    except OSError:
        cap = ""
    color, label = CAP_STYLE.get(cap, (DIM, "○ no cap"))
    return f"{color}{label}{RESET}"


def segment_model(data):
    model = data.get("model") or {}
    name = model.get("display_name") or model.get("id") or ""
    if not name:
        return None
    big = f" {DIM}1M{RESET}" if "[1m]" in (model.get("id") or "") else ""
    return f"{BOLD}{name}{RESET}{big}"


def find_effort(data, tail, head):
    # Native field (v2.1.119+): effort.level — the live session value, incl.
    # mid-session /effort changes. Absent on a native-era payload = the model
    # has no effort parameter, so the fallbacks would mislead; show nothing.
    val = data.get("effort")
    if isinstance(val, dict):
        val = val.get("level")
    if isinstance(val, str) and val:
        return val
    if "context_window" in data:
        return None
    # Latest "/effort" output in the transcript (covers session-only overrides).
    # Only trust user-type entries — the command's stdout lands there; assistant
    # entries can quote the same phrase in code or prose (self-match trap).
    for chunk in (tail, head):
        for line in reversed(chunk.splitlines()):
            if "Set effort level to " not in line:
                continue
            try:
                if json.loads(line).get("type") != "user":
                    continue
            except ValueError:
                continue
            hit = re.search(r"Set effort level to (low|medium|high|xhigh|max)\b", line)
            if hit:
                return hit.group(1)
    try:
        with open(os.path.join(HOME, ".claude", "settings.json")) as f:
            val = json.load(f).get("effortLevel")
        if isinstance(val, str) and val:
            return val
    except Exception:
        pass
    return None


def segment_effort(data, tail, head):
    effort = find_effort(data, tail, head)
    if not effort:
        return None
    style = EFFORT_STYLE.get(effort, "")
    return f"{style}⚡{effort}{RESET}"


def human_tokens(n):
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}".rstrip("0").rstrip(".") + "M"
    return f"{round(n / 1000)}k"


def segment_context(data, tail):
    # Native context_window block first (v2.1.6+): used_percentage and
    # context_window_size are authoritative — input-only definition, 1M
    # windows reported directly, compaction tracked exactly. Fields are null
    # right after /compact and before the first response; fall through then.
    native = data.get("context_window")
    native = native if isinstance(native, dict) else {}
    used = native.get("total_input_tokens")
    if used is None:
        cur = native.get("current_usage") or {}
        if isinstance(cur, dict) and cur.get("input_tokens") is not None:
            used = (cur.get("input_tokens") or 0) \
                + (cur.get("cache_creation_input_tokens") or 0) \
                + (cur.get("cache_read_input_tokens") or 0)
    pct = native.get("used_percentage")
    if pct is None and isinstance(native.get("remaining_percentage"), (int, float)):
        pct = 100 - native["remaining_percentage"]
    if used is None:
        # Legacy fallback: last main-chain assistant usage in the transcript,
        # same input-only sum as the native definition.
        for line in reversed(tail.splitlines()):
            if '"usage"' not in line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get("type") != "assistant" or entry.get("isSidechain"):
                continue
            usage = (entry.get("message") or {}).get("usage") or {}
            if "input_tokens" not in usage:
                continue
            used = (usage.get("input_tokens") or 0) \
                + (usage.get("cache_creation_input_tokens") or 0) \
                + (usage.get("cache_read_input_tokens") or 0)
            break
    if used is None and pct is None:
        return None
    model_id = (data.get("model") or {}).get("id") or ""
    window = native.get("context_window_size") \
        or (1_000_000 if "[1m]" in model_id else 200_000)
    if pct is None:
        pct = used * 100 / window
    pct = max(0, min(100, round(pct)))
    color = COLORS["green"] if pct < 60 else COLORS["yellow"] if pct < 80 else COLORS["red"]
    filled = min(8, round(pct * 8 / 100))
    bar = "▰" * filled + "▱" * (8 - filled)
    tokens = f" {DIM}{human_tokens(used)}/{human_tokens(window)}{RESET}" if used is not None else ""
    return f"{color}{bar} {pct}%{RESET}{tokens}"


def segment_cost(data):
    cost = data.get("cost") or {}
    parts = []
    usd = cost.get("total_cost_usd")
    if isinstance(usd, (int, float)) and usd > 0:
        parts.append(f"${usd:.2f}")
    added, removed = cost.get("total_lines_added"), cost.get("total_lines_removed")
    if added or removed:
        parts.append(f"{COLORS['green']}+{added or 0}{RESET}{DIM}/{RESET}{COLORS['red']}-{removed or 0}{RESET}")
    return f"{DIM}{parts[0]}{RESET} {parts[1]}" if len(parts) == 2 \
        else (parts[0] if len(parts) == 1 else None)


def segment_limits(data):
    limits = data.get("rate_limits")
    if not isinstance(limits, dict):
        return None
    parts = []
    for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
        pct = (limits.get(key) or {}).get("used_percentage")
        if isinstance(pct, (int, float)):
            parts.append((label, round(pct)))
    if not parts:
        return None
    worst = max(p for _, p in parts)
    color = DIM if worst < 50 else COLORS["yellow"] if worst < 80 else COLORS["red"]
    return f"{color}⏱ " + "·".join(f"{l} {p}%" for l, p in parts) + RESET


def segment_git(cwd):
    def git(*args):
        return subprocess.run(
            ["git", "-C", cwd, *args],
            capture_output=True, text=True, timeout=0.2,
        ).stdout.strip()

    branch = git("symbolic-ref", "--short", "-q", "HEAD") or git("rev-parse", "--short", "HEAD")
    if not branch:
        return None
    try:
        dirty = "*" if git("status", "--porcelain", "-uno", "--no-renames") else ""
    except subprocess.TimeoutExpired:
        dirty = "?"
    return f"{COLORS['cyan']}⎇ {branch}{dirty}{RESET}"


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}

    tail = head = ""
    transcript = data.get("transcript_path")
    if transcript:
        try:
            tail, head = read_chunks(transcript)
        except OSError:
            pass

    cwd = (data.get("workspace") or {}).get("current_dir") or data.get("cwd") or os.getcwd()
    segments = []
    for build in (
        lambda: segment_cap(data),
        lambda: segment_model(data),
        lambda: segment_effort(data, tail, head),
        lambda: segment_context(data, tail),
        lambda: segment_cost(data),
        lambda: segment_limits(data),
        lambda: segment_git(cwd),
        lambda: f"{DIM}{os.path.basename(cwd)}{RESET}",
    ):
        try:
            seg = build()
        except Exception:
            seg = None
        if seg:
            segments.append(seg)
    print(SEP.join(segments))


if __name__ == "__main__":
    main()

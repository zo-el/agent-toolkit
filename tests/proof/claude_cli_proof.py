#!/usr/bin/env python3
"""Deterministic harness checks for the Release A Slice 1 real-Claude proof gate.

This module intentionally does not call the Claude CLI during normal tests. It
builds the approved command shape, validates the compact fixture/oracle breadth,
and validates preserved ledgers/artifacts so failed/capped slots remain evidence
instead of crashing or being silently rerun.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "claude-cli-proof"
DEFAULT_CLAUDE = Path("/home/zachariah/.local/bin/claude")
MAX_INVOCATIONS = 10
TIMEOUT_SECONDS = 120
REQUIRED_SUCCESS_SLOTS = {f"B{i}" for i in range(1, 6)} | {f"C{i}" for i in range(1, 6)}
REQUIRED_CONTROLS = {
    "--print",
    "--model",
    "--max-budget-usd",
    "--tools",
    "--permission-mode",
    "--setting-sources",
    "--output-format",
    "--json-schema",
    "--mcp-config",
    "--strict-mcp-config",
}
REQUIRED_LAUNCH_CONTROLS = {
    "neutral_cwd",
    "timeout_seconds",
    "max_invocations",
    "no_retry",
    "strict_empty_mcp",
    "read_only_tools",
    "plan_permission_mode",
    "project_setting_sources",
    "source_sha",
    "fixture_revision",
    "next_slot_requires_ledger_state",
    "actual_resume_slots",
}
REQUIRED_BEHAVIORS = {
    "single_lane",
    "final_output_quality",
    "two_independent_lanes",
    "related_lanes",
    "conflicting_assumptions",
    "stale_context",
    "task_tools_absent_fallback",
    "resume_seed",
    "actual_resume",
}
METRIC_KEYS = ("input_tokens", "output_tokens", "turns", "tool_calls", "elapsed_ms")
MAX_BUDGET_USD = "0.25"
ACTUAL_RESUME_PREDECESSOR = {"B5": "B4", "C5": "C4"}
REVIEWED_HEAD_TOKEN = "<reviewed-head-sha>"
FIXTURE_DIR_TOKEN = "<fixture-dir>"
ALLOWED_LEDGER_KEYS = {
    "created_at",
    "max_invocations",
    "source_sha",
    "fixture_revision",
    "launch_controls",
    "invocations",
    "append_only_attempts",
    "append_only_attempts_digest",
}
ALLOWED_INVOCATION_KEYS = {
    "slot",
    "artifact",
    "started_at",
    "ended_at",
    "exit_status",
    "timed_out",
    "budget_capped",
    "command_digest",
    "resume_from_session_id",
    "command",
}
ALLOWED_ATTEMPT_KEYS = {
    "attempt_index",
    "slot",
    "artifact",
    "exit_status",
    "timed_out",
    "budget_capped",
}


class ProofError(Exception):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 - CLI validator reports context
        raise ProofError(f"{path}: cannot load JSON: {exc}") from exc


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ProofError(message)


def stable_digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def fixture_dir(raw: str | None) -> Path:
    return Path(raw).resolve() if raw else DEFAULT_FIXTURE_DIR


def git_head_sha() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True).strip()
    except Exception as exc:  # noqa: BLE001 - surface deterministic proof context
        raise ProofError(f"cannot resolve reviewed head SHA from git: {exc}") from exc


def resolve_fixture_value(value: Any, path: Path) -> Any:
    if value == REVIEWED_HEAD_TOKEN:
        return git_head_sha()
    if value == FIXTURE_DIR_TOKEN:
        return str(path)
    if isinstance(value, list):
        return [resolve_fixture_value(item, path) for item in value]
    if isinstance(value, dict):
        return {key: resolve_fixture_value(item, path) for key, item in value.items()}
    return value


def fixture_revision_payload(manifest: dict[str, Any], lanes: dict[str, Any], schema: dict[str, Any]) -> dict[str, Any]:
    revision_manifest = json.loads(json.dumps(manifest))
    launch = revision_manifest.get("launch_controls", {})
    if isinstance(launch, dict):
        launch.pop("fixture_revision", None)
    return {"manifest": revision_manifest, "lanes": lanes, "schema": schema}


def validate_fixtures(path: Path) -> dict[str, Any]:
    manifest = load_json(path / "scenario_manifest.json")
    lanes = load_json(path / "lane_context_fixture.json")
    schema = load_json(path / "claude_output_schema.json")
    empty_mcp = load_json(path / "empty-mcp.json")
    revision = stable_digest(fixture_revision_payload(manifest, lanes, schema))
    resolved_source_sha = resolve_fixture_value(manifest.get("source_sha"), path)

    require(empty_mcp == {"mcpServers": {}}, "empty-mcp.json must prove strict empty MCP")
    require(manifest.get("source_sha"), "manifest must pin source_sha for launch control")
    require(manifest.get("source_sha") != "b7011ad5993f705b538009008bb079fdfedcd753", "manifest source_sha must not pin the PR base SHA")
    require(manifest.get("max_invocations") == MAX_INVOCATIONS, "manifest must cap invocations at 10")
    require(manifest.get("required_controls") and REQUIRED_CONTROLS <= set(manifest["required_controls"]), "manifest missing required CLI safety/resource controls")
    launch = manifest.get("launch_controls", {})
    require(REQUIRED_LAUNCH_CONTROLS <= set(launch), f"manifest missing launch controls: {sorted(REQUIRED_LAUNCH_CONTROLS - set(launch))}")
    require(launch.get("neutral_cwd") == FIXTURE_DIR_TOKEN, "committed launch control neutral_cwd must stay portable")
    resolved_launch = resolve_fixture_value(launch, path)
    require(resolved_launch.get("neutral_cwd") == str(path), "launch control must force neutral fixture-only cwd")
    require(launch.get("timeout_seconds") == TIMEOUT_SECONDS, "launch control must pin 120s timeout")
    require(launch.get("max_invocations") == MAX_INVOCATIONS, "launch control must cap ten-slot envelope")
    require(launch.get("no_retry") is True, "launch control must refuse retries")
    require(launch.get("strict_empty_mcp") is True, "launch control must require strict empty MCP")
    require(launch.get("read_only_tools") == ["Read"], "launch control must restrict tools to Read")
    require(launch.get("plan_permission_mode") is True, "launch control must use plan permission mode")
    require(launch.get("project_setting_sources") is True, "launch control must use project setting sources only")
    require(resolve_fixture_value(launch.get("source_sha"), path) == resolved_source_sha, "launch source_sha must match manifest source_sha")
    require(launch.get("fixture_revision") == revision, "launch fixture_revision must match deterministic fixture digest")
    require(launch.get("next_slot_requires_ledger_state") is True, "launch control must require ledger state before each next slot")
    require(launch.get("actual_resume_slots") == ACTUAL_RESUME_PREDECESSOR, "launch control must encode B5/C5 actual-resume predecessors")
    require(schema.get("type") == "object", "Claude output schema must be an object schema")

    state = lanes.get("platform_state", {})
    require(state.get("task_tools_available") is True, "platform fixture must include task tools available")
    seen_lane_ids: set[str] = set()
    seen_numbers: set[int] = set()
    for lane in state.get("lanes", []):
        lane_id = lane.get("platform_lane_id")
        number = lane.get("lane_number")
        subject = lane.get("lane_subject", "")
        require(lane_id and lane_id not in seen_lane_ids, f"duplicate/missing platform_lane_id: {lane_id}")
        require(number not in seen_numbers, f"duplicate lane number: {number}")
        require(subject.startswith(f"#{number} "), f"lane subject lacks matching #N prefix: {subject}")
        seen_lane_ids.add(lane_id)
        seen_numbers.add(number)

    for capsule in lanes.get("capsules", []):
        require(capsule.get("platform_lane_id") in seen_lane_ids, f"capsule not keyed to a platform lane: {capsule}")
        number = capsule.get("lane_number")
        require(capsule.get("lane_subject", "").startswith(f"#{number} "), f"capsule lane #N mismatch: {capsule}")
        forbidden = set(capsule) & {"status", "owner", "assignee", "dependencies", "supplemental_status", "supplemental_owner", "supplemental_dependencies"}
        require(not forbidden, f"capsule duplicates/overrides canonical platform truth: {sorted(forbidden)}")

    negative = lanes.get("negative_records", {})
    override = set(negative.get("supplemental_override", {}))
    require({"supplemental_status", "supplemental_owner", "supplemental_dependencies"} <= override, "override negative missing canonical override fields")
    require(negative.get("custom_ledger_only_recovery", {}).get("task_tools_available") is True, "custom-ledger-only negative must apply when task tools exist")
    require(negative.get("fallback_masquerade", {}).get("non_platform_persisted") is False, "fallback masquerade negative must be invalid")
    require(negative.get("stale_action", {}).get("freshness_checked") is False, "stale action negative must omit freshness check")
    require(negative.get("conflict_without_blocker", {}).get("visible_blocker") is False, "conflict negative must lack visible blocker")

    fallback = lanes.get("fallback_record", {})
    require(fallback.get("fallback_reason") == "task_tools_absent", "fallback reason must be task_tools_absent")
    require(fallback.get("reduced_fidelity") is True, "fallback must be reduced_fidelity")
    require(fallback.get("non_platform_persisted") is True, "fallback must be non_platform_persisted")

    covered: set[str] = set()
    for slot, spec in manifest.get("scenarios", {}).items():
        require(slot in {"B1", "B2", "B3", "B4", "B5"}, f"unexpected baseline slot {slot}")
        covers = set(spec.get("covers", []))
        require(bool(covers), f"{slot} has no coverage claims")
        require(bool(spec.get("oracle")), f"{slot} missing oracle")
        covered.update(covers)
    require(REQUIRED_BEHAVIORS <= covered, f"missing required behavior coverage: {sorted(REQUIRED_BEHAVIORS - covered)}")

    prompt_slots = {p.stem.removeprefix("prompt_") for p in path.glob("prompt_*.txt")}
    require({f"B{i}" for i in range(1, 6)} | {f"C{i}" for i in range(1, 6)} <= prompt_slots, "missing B/C prompt templates")
    return {"fixture_dir": str(path), "source_sha": resolved_source_sha, "fixture_revision": revision, "covered": sorted(covered)}


def launch_controls(path: Path) -> dict[str, Any]:
    fixtures = validate_fixtures(path)
    return {
        "neutral_cwd": str(path),
        "timeout_seconds": TIMEOUT_SECONDS,
        "max_invocations": MAX_INVOCATIONS,
        "no_retry": True,
        "strict_empty_mcp": True,
        "read_only_tools": ["Read"],
        "plan_permission_mode": True,
        "project_setting_sources": True,
        "source_sha": fixtures["source_sha"],
        "fixture_revision": fixtures["fixture_revision"],
        "next_slot_requires_ledger_state": True,
        "actual_resume_slots": ACTUAL_RESUME_PREDECESSOR,
    }


def build_command(slot: str, path: Path, claude: Path = DEFAULT_CLAUDE, resume_id: str | None = None) -> dict[str, Any]:
    allowed_slots = {f"B{i}" for i in range(1, 6)} | {f"C{i}" for i in range(1, 6)}
    require(slot in allowed_slots, f"unsupported slot {slot}")
    controls = launch_controls(path)
    predecessor = ACTUAL_RESUME_PREDECESSOR.get(slot)
    if predecessor:
        require(resume_id is not None and resume_id != "", f"{slot}: actual resume requires --resume from {predecessor}")
    schema = (path / "claude_output_schema.json").read_text(encoding="utf-8")
    prompt = (path / f"prompt_{slot}.txt").read_text(encoding="utf-8")
    argv = [
        str(claude),
        "--print",
        "--model",
        "sonnet",
        "--max-budget-usd",
        MAX_BUDGET_USD,
        "--tools",
        "Read",
        "--permission-mode",
        "plan",
        "--setting-sources",
        "project",
        "--output-format",
        "json",
        "--json-schema",
        schema,
        "--mcp-config",
        str(path / "empty-mcp.json"),
        "--strict-mcp-config",
    ]
    if resume_id:
        argv += ["--resume", resume_id]
    argv += [
        "--add-dir",
        str(path),
    ]
    digest_argv = ["<json-schema>" if item == schema else item for item in argv]
    return {
        "slot": slot,
        "stdin_prompt": prompt,
        "argv": argv,
        "cwd": controls["neutral_cwd"],
        "timeout_seconds": controls["timeout_seconds"],
        "resume_parent_slot": predecessor,
        "launch_controls": controls,
        "command_digest": hashlib.sha256(json.dumps(digest_argv, separators=(",", ":")).encode()).hexdigest(),
        "safety_note": "Prompt is supplied on stdin, not as a trailing argv after variadic --add-dir.",
    }


def selected_blob(out: dict[str, Any]) -> str:
    fields = [out.get("selected_context", []), out.get("excluded_context", []), out.get("decisions", []), out.get("provenance", []), out.get("blocks", []), out.get("recovery_view", {}), out.get("fallback", {}), out.get("summary", "")]
    return json.dumps(fields, sort_keys=True)


def oracle_self_check_passed(oracle: dict[str, Any]) -> bool:
    """Validate the oracle self-check contract using only explicit pass markers."""
    if oracle.get("passed") is False or oracle.get("match") is False:
        return False
    return oracle.get("passed") is True or oracle.get("match") is True


def validate_success_output(slot: str, result: dict[str, Any]) -> None:
    base = "B" + slot[1] if slot.startswith("C") else slot
    require(result.get("slot") == slot, f"{slot}: result slot mismatch")
    for key in ("selected_context", "excluded_context", "decisions", "provenance", "blocks"):
        require(isinstance(result.get(key), list), f"{slot}: {key} must be a list")
    require(isinstance(result.get("oracle_self_check"), dict), f"{slot}: missing oracle_self_check object")
    oracle = result["oracle_self_check"]
    require(oracle_self_check_passed(oracle), f"{slot}: oracle_self_check must report explicit passed/match true")
    blob = selected_blob(result)
    if base == "B1":
        require("cap_2" in blob and "pl_2" in blob, f"{slot}: must select only target lane #2 context")
        require("cap_1" in json.dumps(result.get("excluded_context", [])) and "cap_3" in json.dumps(result.get("excluded_context", [])), f"{slot}: must exclude unrelated lanes")
    elif base == "B2":
        require("cap_1" in blob and "cap_3" in blob, f"{slot}: must include both independent target lanes")
        selected_blob_only = json.dumps(result.get("selected_context", []), sort_keys=True)
        require("cap_2" not in selected_blob_only and "pl_2" not in selected_blob_only, f"{slot}: selected out-of-scope lane #2 context")
    elif base == "B3":
        require("cap_1.f1" in blob or "f1" in blob, f"{slot}: missing explicit cross-lane provenance")
        require(bool(result.get("blocks")), f"{slot}: conflict must be fail-visible")
    elif base == "B4":
        for token in ("task_tools_absent", "reduced_fidelity", "non_platform_persisted"):
            require(token in blob, f"{slot}: missing fallback label {token}")
        require(bool(result.get("blocks")), f"{slot}: stale/fallback conditions must block or warn")
    elif base == "B5":
        require("platform_state" in blob, f"{slot}: recovery must name platform_state as live truth")
        require("capsule" in blob.lower(), f"{slot}: recovery must name capsule supplements")


def artifact_result(artifact: dict[str, Any]) -> dict[str, Any]:
    result = artifact.get("result")
    if isinstance(result, dict):
        wrapper = artifact.get("wrapper", {})
        if isinstance(wrapper, dict) and wrapper.get("session_id"):
            result = dict(result)
            result["session_id"] = wrapper["session_id"]
        return result
    return artifact


def has_failed_slot_evidence(artifact: dict[str, Any]) -> bool:
    """Return true when a failed/capped slot preserves a concrete failure reason."""
    for key in ("stderr", "error", "parse_error"):
        if artifact.get(key):
            return True
    for key in ("raw_summary", "wrapper"):
        summary = artifact.get(key)
        if not isinstance(summary, dict):
            continue
        if summary.get("errors") or summary.get("subtype") or summary.get("terminal_reason"):
            return True
    return False


def require_known_keys(mapping: dict[str, Any], allowed: set[str], context: str) -> None:
    unknown = sorted(set(mapping) - allowed)
    require(not unknown, f"{context}: unknown fields are not allowed: {unknown}")


def normalize_record_value(value: Any, fixtures: Path) -> Any:
    return resolve_fixture_value(value, fixtures)


def validate_attempt_history(ledger: dict[str, Any], invocations: list[dict[str, Any]], fixtures: Path, *, require_complete: bool) -> None:
    attempts = ledger.get("append_only_attempts")
    digest = ledger.get("append_only_attempts_digest")
    if require_complete:
        require(isinstance(attempts, list), "proof-complete ledger must include append_only_attempts")
        require(isinstance(digest, str) and bool(digest), "proof-complete ledger must include append_only_attempts_digest")
    if attempts is None:
        return
    require(isinstance(attempts, list), "append_only_attempts must be a list")
    require(digest == stable_digest(attempts), "append_only_attempts_digest must match the full append-only attempt history")
    if require_complete:
        require(len(attempts) == MAX_INVOCATIONS, "proof-complete ledger must preserve exactly ten append-only attempts")
        require(len(invocations) == MAX_INVOCATIONS, "proof-complete ledger must list exactly ten successful invocation records")

    seen_indexes: list[int] = []
    for idx, attempt in enumerate(attempts, start=1):
        require(isinstance(attempt, dict), f"attempt {idx}: must be an object")
        require_known_keys(attempt, ALLOWED_ATTEMPT_KEYS, f"attempt {idx}")
        require(attempt.get("attempt_index") == idx, f"attempt {idx}: attempt_index must be append-only and gapless")
        seen_indexes.append(idx)
        if require_complete:
            require(attempt.get("exit_status") == 0, f"attempt {idx}: nonzero exit keeps proof incomplete")
            require(attempt.get("timed_out") is False, f"attempt {idx}: timeout keeps proof incomplete")
            require(attempt.get("budget_capped") in (False, None), f"attempt {idx}: budget cap keeps proof incomplete")

    if require_complete:
        for idx, invocation in enumerate(invocations, start=1):
            attempt = attempts[idx - 1]
            for key in ("slot", "artifact", "exit_status", "timed_out"):
                require(normalize_record_value(attempt.get(key), fixtures) == normalize_record_value(invocation.get(key), fixtures), f"attempt {idx}: {key} must match invocation history")
            require(bool(normalize_record_value(attempt.get("budget_capped", False), fixtures)) == bool(normalize_record_value(invocation.get("budget_capped", False), fixtures)), f"attempt {idx}: budget_capped must match invocation history")


def validate_ledger(path: Path, fixtures: Path = DEFAULT_FIXTURE_DIR) -> dict[str, Any]:
    ledger = load_json(path)
    invocations = ledger.get("invocations", [])
    expected_controls = launch_controls(fixtures)
    require(isinstance(ledger, dict), "ledger must be an object")
    require_known_keys(ledger, ALLOWED_LEDGER_KEYS, "ledger")
    require(isinstance(invocations, list), "ledger invocations must be a list")
    require(ledger.get("max_invocations") == MAX_INVOCATIONS, "ledger must record ten-slot max_invocations")
    require(len(invocations) <= MAX_INVOCATIONS, "ledger exceeds ten-slot envelope")
    require(resolve_fixture_value(ledger.get("source_sha"), fixtures) == expected_controls["source_sha"], "ledger source_sha must match approved fixture source_sha")
    require(ledger.get("source_sha") != "b7011ad5993f705b538009008bb079fdfedcd753", "ledger source_sha must not pin the PR base SHA")
    require(ledger.get("fixture_revision") == expected_controls["fixture_revision"], "ledger fixture_revision must match approved fixture revision")
    launch = ledger.get("launch_controls", {})
    require(isinstance(launch, dict), "ledger launch_controls must be an object")
    require_known_keys(launch, REQUIRED_LAUNCH_CONTROLS, "ledger launch_controls")
    require(REQUIRED_LAUNCH_CONTROLS <= set(launch), f"ledger missing launch controls: {sorted(REQUIRED_LAUNCH_CONTROLS - set(launch))}")
    for key, expected in expected_controls.items():
        require(resolve_fixture_value(launch.get(key), fixtures) == expected, f"ledger launch control {key} must match approved fixture control")

    successes: dict[str, dict[str, Any]] = {}
    session_ids: dict[str, str] = {}
    failures: list[str] = []
    artifact_root = path.parent
    for idx, item in enumerate(invocations):
        require(isinstance(item, dict), f"invocation {idx}: must be an object")
        require_known_keys(item, ALLOWED_INVOCATION_KEYS, f"invocation {idx}")
        slot = item.get("slot")
        require(slot in {f"B{i}" for i in range(1, 6)} | {f"C{i}" for i in range(1, 6)}, f"invocation {idx}: bad slot {slot}")
        artifact_path = Path(item.get("artifact", ""))
        if not artifact_path.is_absolute():
            artifact_path = artifact_root / artifact_path
        require(artifact_path.exists(), f"{slot}: artifact missing: {artifact_path}")
        artifact = load_json(artifact_path)
        exit_status = artifact.get("exit_status", item.get("exit_status"))
        if exit_status != 0 or artifact.get("timed_out") or artifact.get("budget_capped"):
            require(has_failed_slot_evidence(artifact), f"{slot}: failed slot must preserve error evidence")
            failures.append(slot)
            continue
        predecessor = ACTUAL_RESUME_PREDECESSOR.get(slot)
        if predecessor:
            require(predecessor in session_ids, f"{slot}: actual resume requires successful prior {predecessor}")
            require(item.get("resume_from_session_id") == session_ids[predecessor], f"{slot}: ledger must record resume_from_session_id from {predecessor}")
            command = item.get("command", {})
            argv = command.get("argv", []) if isinstance(command, dict) else []
            require("--resume" in argv, f"{slot}: command argv missing --resume")
            resume_idx = argv.index("--resume")
            require(resume_idx + 1 < len(argv) and argv[resume_idx + 1] == session_ids[predecessor], f"{slot}: --resume must use {predecessor} session_id")
            require("--add-dir" not in argv[:resume_idx], f"{slot}: --resume must be emitted before variadic --add-dir")
        result = artifact_result(artifact)
        validate_success_output(slot, result)
        session_id = result.get("session_id")
        if not isinstance(session_id, str) or not session_id:
            raise ProofError(f"{slot}: successful artifact must preserve session_id")
        successes[slot] = artifact
        session_ids[slot] = session_id

    comparisons = compare_pairs(successes)
    return {"ledger": str(path), "invocations": len(invocations), "successes": sorted(successes), "failed_evidence_slots": failures, "comparisons": comparisons}


def validate_proof_complete(path: Path, fixtures: Path = DEFAULT_FIXTURE_DIR) -> dict[str, Any]:
    """Validate that a ledger is complete release proof, not merely preserved evidence."""
    ledger = load_json(path)
    invocations = ledger.get("invocations", []) if isinstance(ledger, dict) else []
    validate_attempt_history(ledger, invocations, fixtures, require_complete=True)
    result = validate_ledger(path, fixtures)
    successes = set(result["successes"])
    failures = result["failed_evidence_slots"]
    missing = sorted(REQUIRED_SUCCESS_SLOTS - successes)
    require(not missing, f"proof incomplete; missing successful slots: {missing}")
    require(not failures, f"proof incomplete; failed evidence slots are not release proof: {failures}")
    comparisons = result.get("comparisons", {})
    pairs = comparisons.get("pairs", {}) if isinstance(comparisons, dict) else {}
    compared_pairs = set(pairs)
    expected_pairs = {f"B{i}/C{i}" for i in range(1, 6)}
    missing_pairs = sorted(expected_pairs - compared_pairs)
    require(not missing_pairs, f"proof incomplete; missing matched comparison pairs: {missing_pairs}")
    return {**result, "proof_complete": True}


def metric_value(artifact: dict[str, Any], key: str) -> float | None:
    metrics = artifact.get("metrics", {}) | artifact.get("usage", {})
    value = metrics.get(key)
    if value is None and key == "elapsed_ms":
        value = metrics.get("duration_ms")
    if isinstance(value, (int, float)):
        return float(value)
    return None


def compare_pairs(successes: dict[str, dict[str, Any]]) -> dict[str, Any]:
    ratios: dict[str, list[float]] = {key: [] for key in METRIC_KEYS}
    pair_reports: dict[str, Any] = {}
    for idx in range(1, 6):
        b_slot, c_slot = f"B{idx}", f"C{idx}"
        if b_slot not in successes or c_slot not in successes:
            continue
        pair: dict[str, Any] = {}
        b_result = artifact_result(successes[b_slot])
        c_result = artifact_result(successes[c_slot])
        require(c_result.get("oracle_self_check", {}).get("passed") is not False, f"{c_slot}: oracle self-check reports failure")
        require(len(json.dumps(c_result.get("selected_context", []))) <= max(1, len(json.dumps(b_result.get("selected_context", [])))) * 2, f"{c_slot}: selected context appears to grow suspiciously")
        for key in METRIC_KEYS:
            b_val = metric_value(successes[b_slot], key)
            c_val = metric_value(successes[c_slot], key)
            if b_val is None or c_val is None:
                continue
            if b_val == 0:
                pair[key] = {"baseline": b_val, "candidate": c_val, "delta": c_val - b_val}
            else:
                ratio = c_val / b_val
                ratios[key].append(ratio)
                regression = ratio > 1.2
                pair[key] = {"baseline": b_val, "candidate": c_val, "ratio": ratio, "regression_over_20pct": regression}

        pair_reports[f"B{idx}/C{idx}"] = pair
    medians = {key: statistics.median(values) for key, values in ratios.items() if values}
    return {"pairs": pair_reports, "aggregate_median_ratios": medians}


def validate_oracle_contract() -> dict[str, Any]:
    cases = {
        "explicit-passed-true": ({"passed": True, "notes": "not authoritative"}, True),
        "explicit-match-true": ({"match": True, "notes": "not authoritative"}, True),
        "explicit-passed-false": ({"passed": False, "checks": {"nested": True}}, False),
        "explicit-match-false": ({"match": False, "checks": {"nested": True}}, False),
        "explicit-false-overrides-match-true": ({"passed": False, "match": True}, False),
        "nested-all-true-ambiguous": ({"checks": {"must_select": {"cap_2": True}, "must_exclude": [True, True]}, "notes": "diagnostic only"}, False),
        "nested-false-ambiguous": ({"overall": True, "checks": {"must_select": True, "must_exclude": {"cap_1": False}}}, False),
        "metadata-notes-ignored": ({"notes": "all satisfied", "explanation": "satisfied"}, False),
    }
    for label, (oracle, expected) in cases.items():
        require(oracle_self_check_passed(oracle) is expected, f"oracle contract case failed: {label}")
    return {"oracle_contract_cases": sorted(cases)}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture-dir")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate-fixtures")
    build = sub.add_parser("build-command")
    build.add_argument("slot")
    build.add_argument("--resume-id")
    led = sub.add_parser("validate-ledger")
    led.add_argument("ledger")
    complete = sub.add_parser("validate-proof-complete")
    complete.add_argument("ledger")
    sub.add_parser("validate-oracle-contract")
    args = parser.parse_args(argv)

    try:
        fixtures = fixture_dir(args.fixture_dir)
        if args.cmd == "validate-fixtures":
            result = validate_fixtures(fixtures)
        elif args.cmd == "build-command":
            validate_fixtures(fixtures)
            result = build_command(args.slot, fixtures, resume_id=args.resume_id)
        elif args.cmd == "validate-ledger":
            result = validate_ledger(Path(args.ledger).resolve(), fixtures)
        elif args.cmd == "validate-proof-complete":
            result = validate_proof_complete(Path(args.ledger).resolve(), fixtures)
        elif args.cmd == "validate-oracle-contract":
            result = validate_oracle_contract()
        else:  # pragma: no cover
            raise AssertionError(args.cmd)
    except ProofError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

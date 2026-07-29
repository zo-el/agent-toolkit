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
import os
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FIXTURE_DIR = REPO_ROOT / "tests" / "fixtures" / "claude-cli-proof"
DEFAULT_CLAUDE = Path("/home/zachariah/.local/bin/claude")
MAX_INVOCATIONS = 10
TIMEOUT_SECONDS = 120
EXPECTED_SLOT_ORDER = [f"B{i}" for i in range(1, 6)] + [f"C{i}" for i in range(1, 6)]
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
    "release_proof_mode",
    "control_manifest",
    "control_manifest_digest",
    "preflight",
    "preflight_digest",
    "event_journal",
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
    "raw_dir",
    "raw_artifact_digests",
    "artifact_digest",
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


class PacketUnproven(ProofError):
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


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relpath(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve()))


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    try:
        rows = []
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                rows.append(json.loads(line))
        return rows
    except Exception as exc:  # noqa: BLE001 - CLI validator reports context
        raise ProofError(f"{path}: cannot load JSONL journal: {exc}") from exc


def write_once(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    try:
        fd = os.open(path, flags, 0o644)
    except FileExistsError as exc:
        raise PacketUnproven(f"write-once artifact already exists: {path}") from exc
    with os.fdopen(fd, "wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


def write_once_json(path: Path, value: Any) -> None:
    write_once(path, json.dumps(value, indent=2, sort_keys=True).encode("utf-8") + b"\n")


def append_journal_event(journal: Path, event: dict[str, Any]) -> dict[str, Any]:
    rows = read_jsonl(journal) if journal.exists() else []
    seq = len(rows) + 1
    prev_hash = rows[-1]["event_hash"] if rows else "0" * 64
    payload = {"seq": seq, "prev_hash": prev_hash, **event}
    event_hash = stable_digest(payload)
    row = {**payload, "event_hash": event_hash}
    journal.parent.mkdir(parents=True, exist_ok=True)
    with journal.open("ab") as handle:
        handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")).encode("utf-8") + b"\n")
        handle.flush()
        os.fsync(handle.fileno())
    return row


def rewrite_journal_hash_chain(path: Path, rows: list[dict[str, Any]]) -> None:
    """Rewrite rows with a valid seq/prev/event hash chain for deterministic tamper tests."""
    rewritten = []
    prev_hash = "0" * 64
    for seq, row in enumerate(rows, start=1):
        payload = dict(row)
        payload.pop("event_hash", None)
        payload["seq"] = seq
        payload["prev_hash"] = prev_hash
        event_hash = stable_digest(payload)
        rewritten.append({**payload, "event_hash": event_hash})
        prev_hash = event_hash
    path.write_text("\n".join(json.dumps(row, sort_keys=True, separators=(",", ":")) for row in rewritten) + "\n", encoding="utf-8")


def validate_journal_hash_chain(path: Path) -> list[dict[str, Any]]:
    rows = read_jsonl(path)
    prev = "0" * 64
    for expected_seq, row in enumerate(rows, start=1):
        require(row.get("seq") == expected_seq, f"journal seq break at row {expected_seq}")
        require(row.get("prev_hash") == prev, f"journal prev_hash break at row {expected_seq}")
        event_hash = row.get("event_hash")
        body = dict(row)
        body.pop("event_hash", None)
        require(event_hash == stable_digest(body), f"journal event_hash break at row {expected_seq}")
        prev = event_hash
    return rows


def safe_preflight_metadata(raw: dict[str, Any] | None) -> dict[str, Any]:
    metadata = dict(raw or {})
    for key in list(metadata):
        lowered = key.lower()
        if lowered == "secrets_stored":
            continue
        require(not any(token in lowered for token in ("token", "secret", "password", "apikey", "api_key")), "preflight metadata key looks secret-bearing")
    metadata.setdefault("provider", "claude-cli")
    metadata.setdefault("checked_before_first_invocation", True)
    metadata.setdefault("secrets_stored", False)
    require(metadata.get("checked_before_first_invocation") is True, "preflight metadata must be captured before first invocation")
    require(metadata.get("secrets_stored") is False, "preflight metadata must not store secrets")
    return metadata


def fixture_file_digests(path: Path) -> dict[str, str]:
    names = ["scenario_manifest.json", "lane_context_fixture.json", "claude_output_schema.json", "empty-mcp.json"]
    names += [f"prompt_{slot}.txt" for slot in EXPECTED_SLOT_ORDER]
    return {name: file_digest(path / name) for name in names}


def command_shape(argv: list[str]) -> list[str]:
    shaped: list[str] = []
    skip_next = False
    for item in argv:
        if skip_next:
            skip_next = False
            continue
        if item == "--json-schema":
            shaped.extend([item, "<json-schema>"])
            skip_next = True
        elif item == "--resume":
            shaped.extend([item, "<resume-session-id>"])
            skip_next = True
        else:
            shaped.append(item)
    return shaped


def command_digest_from_argv(argv: list[str]) -> str:
    digest_argv: list[str] = []
    skip_next = False
    for item in argv:
        if skip_next:
            digest_argv.append("<json-schema>")
            skip_next = False
            continue
        digest_argv.append(item)
        if item == "--json-schema":
            skip_next = True
    return hashlib.sha256(json.dumps(digest_argv, separators=(",", ":")).encode()).hexdigest()


def control_manifest(path: Path, claude: Path) -> dict[str, Any]:
    fixtures = validate_fixtures(path)
    command_shapes = {}
    for slot in EXPECTED_SLOT_ORDER:
        resume_id = "<resume-session-id>" if slot in ACTUAL_RESUME_PREDECESSOR else None
        command_shapes[slot] = command_shape(build_command(slot, path, claude=claude, resume_id=resume_id)["argv"])
    prompt_digests = {f"prompt_{slot}.txt": file_digest(path / f"prompt_{slot}.txt") for slot in EXPECTED_SLOT_ORDER}
    return {
        "source_head": git_head_sha(),
        "runner_code_digest": file_digest(Path(__file__).resolve()),
        "evaluator_code_digest": file_digest(Path(__file__).resolve()),
        "fixture_revision": fixtures["fixture_revision"],
        "fixture_file_digests": fixture_file_digests(path),
        "prompt_contract_digests": prompt_digests,
        "scenario_contract_digest": file_digest(path / "scenario_manifest.json"),
        "claude_command_shapes": command_shapes,
        "timeout_seconds": TIMEOUT_SECONDS,
        "budget_usd": MAX_BUDGET_USD,
        "expected_slot_order": EXPECTED_SLOT_ORDER,
        "actual_resume_slots": ACTUAL_RESUME_PREDECESSOR,
        "one_invocation_per_slot": True,
        "raw_artifacts_write_once": True,
    }


def load_packet_sidecar(packet: Path, relative: str, digest: str, label: str) -> Any:
    sidecar = packet / relative
    require(sidecar.exists(), f"strict proof missing {label}: {relative}")
    require(file_digest(sidecar) == digest, f"strict proof {label} digest mismatch: {relative}")
    return load_json(sidecar)


def budget_capped_from_explicit_evidence(exit_status: int | None, timed_out: bool, wrapper: dict[str, Any], stderr: str) -> bool:
    """Only explicit wrapper/terminal failures and stderr signatures can mark a budget cap."""
    if exit_status == 0 and not timed_out:
        return False
    explicit_values = []
    for key in ("error", "subtype", "terminal_reason", "termination_reason"):
        value = wrapper.get(key)
        if isinstance(value, str):
            explicit_values.append(value.lower())
    errors = wrapper.get("errors")
    if isinstance(errors, list):
        explicit_values.extend(str(item).lower() for item in errors)
    explicit_values.append(stderr.lower())
    blob = "\n".join(explicit_values)
    signatures = ("budget cap", "budget_capped", "max budget", "maximum budget", "exceeded budget", "cost limit")
    return any(signature in blob for signature in signatures)


def assert_no_pending_start(rows: list[dict[str, Any]]) -> None:
    expected_index = 0
    active_slot: str | None = None
    for row in rows:
        event = row.get("event")
        slot = row.get("slot")
        require(isinstance(slot, str), f"journal row {row.get('seq')}: slot must be a string")
        if event == "invocation_start":
            require(active_slot is None, f"{slot}: overlapping invocation start before completing {active_slot}")
            require(expected_index < len(EXPECTED_SLOT_ORDER), f"{slot}: start exceeds ten-slot envelope")
            require(slot == EXPECTED_SLOT_ORDER[expected_index], f"{slot}: start is not next fixed slot {EXPECTED_SLOT_ORDER[expected_index]}")
            active_slot = slot
        elif event == "invocation_complete":
            require(active_slot == slot, f"{slot}: completion without matching active start")
            expected_index += 1
            active_slot = None
        elif event == "correction":
            continue
        else:
            raise ProofError(f"journal row {row.get('seq')}: unsupported event {event}")
    require(active_slot is None, f"pending invocation start without completion: {active_slot}")


def completed_slots_from_journal(rows: list[dict[str, Any]]) -> list[str]:
    completed: list[str] = []
    active_slot: str | None = None
    for row in rows:
        event = row.get("event")
        slot = row.get("slot")
        if event == "invocation_start":
            require(isinstance(slot, str), f"journal row {row.get('seq')}: slot must be a string")
            active_slot = slot
        elif event == "invocation_complete":
            require(isinstance(slot, str), f"journal row {row.get('seq')}: slot must be a string")
            require(active_slot == slot, f"{slot}: completion without matching active start")
            completed.append(slot)
            active_slot = None
    return completed


def validate_resume_prefix(packet: Path, ledger_path: Path, rows: list[dict[str, Any]]) -> list[str]:
    """Fail closed before spawn unless mutable ledger exactly mirrors immutable completed evidence."""
    ledger = load_json(ledger_path)
    ledger_slots = completed_slots_from_ledger(ledger_path)
    journal_slots = completed_slots_from_journal(rows)
    require(ledger_slots == journal_slots, f"resume ledger slots must exactly match immutable journal completed prefix: ledger={ledger_slots} journal={journal_slots}")

    for item in ledger.get("invocations", []):
        slot = item.get("slot")
        artifact = item.get("artifact")
        require(isinstance(slot, str) and isinstance(artifact, str), f"resume invocation missing slot/artifact: {item}")
        artifact_path = packet / artifact
        require(artifact_path.exists(), f"{slot}: resume normalized artifact missing")
        require(file_digest(artifact_path) == item.get("artifact_digest"), f"{slot}: resume normalized artifact digest mismatch")
        raw_dir = packet / item.get("raw_dir", "")
        require(raw_dir.is_dir(), f"{slot}: resume raw evidence directory missing")
        raw_digests = item.get("raw_artifact_digests", {})
        require(set(raw_digests) == {"stdout.txt", "stderr.txt", "wrapper.json", "exit.json", "timing.json"}, f"{slot}: resume raw evidence manifest incomplete")
        for name, digest in raw_digests.items():
            raw_path = raw_dir / name
            require(raw_path.exists(), f"{slot}: resume raw evidence missing {name}")
            require(file_digest(raw_path) == digest, f"{slot}: resume raw evidence mutated: {name}")

    if len(ledger_slots) < len(EXPECTED_SLOT_ORDER):
        next_slot = EXPECTED_SLOT_ORDER[len(ledger_slots)]
        next_raw_dir = packet / "artifacts" / "raw" / next_slot
        next_normalized = packet / "artifacts" / "normalized" / f"{next_slot}.json"
        require(not next_raw_dir.exists(), f"{next_slot}: resume would overwrite existing raw evidence")
        require(not next_normalized.exists(), f"{next_slot}: resume would overwrite existing normalized evidence")
    return ledger_slots


def validate_strict_packet(path: Path, fixtures: Path) -> dict[str, Any]:
    ledger = load_json(path)
    packet = path.parent
    if ledger.get("release_proof_mode") != "strict-immutable-v1":
        raise PacketUnproven("legacy/current mutable packet is informal/non-strict; strict release proof requires immutable control/preflight/raw/journal sidecars")
    manifest = load_packet_sidecar(packet, ledger.get("control_manifest", ""), ledger.get("control_manifest_digest", ""), "control manifest")
    preflight = load_packet_sidecar(packet, ledger.get("preflight", ""), ledger.get("preflight_digest", ""), "first preflight")
    require(preflight.get("checked_before_first_invocation") is True, "first preflight must be explicitly before first invocation")
    require(preflight.get("secrets_stored") is False, "first preflight must not store secrets")
    require(manifest.get("source_head") == git_head_sha(), "strict proof source/control drift: source HEAD changed")
    require(manifest.get("runner_code_digest") == file_digest(Path(__file__).resolve()), "strict proof source/control drift: runner code changed")
    require(manifest.get("evaluator_code_digest") == file_digest(Path(__file__).resolve()), "strict proof source/control drift: evaluator code changed")
    require(manifest.get("fixture_file_digests") == fixture_file_digests(fixtures), "strict proof source/control drift: fixture files changed")
    require(manifest.get("expected_slot_order") == EXPECTED_SLOT_ORDER, "strict proof must bind fixed ten-slot order")

    journal_rel = ledger.get("event_journal", "")
    journal = packet / journal_rel
    require(journal.exists(), f"strict proof missing event journal: {journal_rel}")
    rows = validate_journal_hash_chain(journal)
    assert_no_pending_start(rows)
    require(not any(row.get("event") == "correction" for row in rows), "strict proof inadmissible after correction event")
    starts = [row for row in rows if row.get("event") == "invocation_start"]
    completes = [row for row in rows if row.get("event") == "invocation_complete"]
    start_slots = [row.get("slot") for row in starts]
    require(start_slots == EXPECTED_SLOT_ORDER, f"strict proof must follow fixed slot order exactly once: {start_slots}")
    require([row.get("slot") for row in completes] == EXPECTED_SLOT_ORDER, "strict proof completions must follow fixed slot order exactly once")
    control_hash = ledger["control_manifest_digest"]
    preflight_hash = ledger["preflight_digest"]
    for row in starts:
        require(row.get("control_manifest_digest") == control_hash, f"{row.get('slot')}: control hash drift before spawn")
        require(row.get("preflight_digest") == preflight_hash, f"{row.get('slot')}: preflight hash drift before spawn")
        require(row.get("source_head") == manifest["source_head"], f"{row.get('slot')}: source drift before spawn")
        require(row.get("timeout_seconds") == TIMEOUT_SECONDS, f"{row.get('slot')}: timeout drift before spawn")
        require(row.get("budget_usd") == MAX_BUDGET_USD, f"{row.get('slot')}: budget drift before spawn")

    invocations = ledger.get("invocations", [])
    require([item.get("slot") for item in invocations] == EXPECTED_SLOT_ORDER, "strict proof ledger invocations must match fixed order")
    starts_by_slot = {row["slot"]: row for row in starts}
    completes_by_slot = {row["slot"]: row for row in completes}
    for item in invocations:
        slot = item["slot"]
        command = item.get("command", {})
        require(isinstance(command, dict), f"{slot}: ledger command must be recorded")
        argv = command.get("argv", [])
        require(isinstance(argv, list) and all(isinstance(arg, str) for arg in argv), f"{slot}: command argv must be recorded as strings")
        require(command_shape(argv) == manifest.get("claude_command_shapes", {}).get(slot), f"{slot}: command shape drift from immutable control manifest")
        require(item.get("command_digest") == command_digest_from_argv(argv), f"{slot}: command_digest does not match recorded argv")
        require(starts_by_slot[slot].get("command_digest") == item.get("command_digest"), f"{slot}: journal start command_digest does not match ledger")
        artifact_path = packet / item["artifact"]
        require(artifact_path.exists(), f"{slot}: normalized artifact missing")
        require(file_digest(artifact_path) == item.get("artifact_digest"), f"{slot}: normalized artifact digest mismatch")
        raw_dir = packet / item.get("raw_dir", "")
        require(raw_dir.is_dir(), f"{slot}: raw evidence directory missing")
        raw_digests = item.get("raw_artifact_digests", {})
        require(set(raw_digests) == {"stdout.txt", "stderr.txt", "wrapper.json", "exit.json", "timing.json"}, f"{slot}: raw evidence manifest incomplete")
        for name, digest in raw_digests.items():
            raw_path = raw_dir / name
            require(raw_path.exists(), f"{slot}: raw evidence missing {name}")
            require(file_digest(raw_path) == digest, f"{slot}: raw evidence mutated: {name}")
        require(completes_by_slot[slot].get("artifact_digest") == item.get("artifact_digest"), f"{slot}: journal completion artifact_digest does not match ledger")
    return {"strict_release_proof": True, "journal_events": len(rows), "control_manifest": ledger["control_manifest"]}


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


def parse_stdout_wrapper(stdout: str) -> tuple[dict[str, Any], dict[str, Any]]:
    try:
        parsed = json.loads(stdout) if stdout.strip() else {}
    except json.JSONDecodeError as exc:
        return {}, {"parse_error": str(exc), "raw_stdout": stdout}
    if isinstance(parsed, dict) and isinstance(parsed.get("result"), dict):
        return parsed, parsed["result"]
    if isinstance(parsed, dict):
        return parsed, parsed
    return {}, {"parse_error": "stdout JSON was not an object", "raw_stdout": stdout}


def completed_slots_from_ledger(ledger_path: Path) -> list[str]:
    if not ledger_path.exists():
        return []
    ledger = load_json(ledger_path)
    invocations = ledger.get("invocations", []) if isinstance(ledger, dict) else []
    slots = [item.get("slot") for item in invocations]
    require(slots == EXPECTED_SLOT_ORDER[: len(slots)], f"resume lineage must be an exact prefix of the fixed slot order: {slots}")
    return slots


def existing_packet_hashes(packet: Path) -> tuple[str, str]:
    ledger_path = packet / "ledger.json"
    require(ledger_path.exists(), "resume requires existing ledger.json")
    ledger = load_json(ledger_path)
    control_rel = ledger.get("control_manifest")
    preflight_rel = ledger.get("preflight")
    require(isinstance(control_rel, str) and isinstance(preflight_rel, str), "resume ledger missing control/preflight sidecars")
    control_hash = ledger.get("control_manifest_digest")
    preflight_hash = ledger.get("preflight_digest")
    require(isinstance(control_hash, str) and isinstance(preflight_hash, str), "resume ledger missing control/preflight hashes")
    require(file_digest(packet / control_rel) == control_hash, "resume control manifest hash mismatch")
    require(file_digest(packet / preflight_rel) == preflight_hash, "resume first preflight hash mismatch")
    return control_hash, preflight_hash


def acquire_packet_lock(packet: Path) -> Path:
    lock = packet / ".runner.lock"
    try:
        write_once(lock, f"pid={os.getpid()}\n".encode("utf-8"))
    except PacketUnproven as exc:
        raise PacketUnproven("duplicate/concurrent runner refused") from exc
    return lock


def run_packet(packet: Path, fixtures: Path, claude: Path, preflight: dict[str, Any] | None = None, *, stop_after_slot: str | None = None) -> dict[str, Any]:
    """Tracked, deterministic packet runner. Tests use a fake Claude executable; production uses the same reviewed code."""
    packet.mkdir(parents=True, exist_ok=True)
    journal = packet / "events.jsonl"
    ledger_path = packet / "ledger.json"
    lock = acquire_packet_lock(packet)
    try:
        if journal.exists():
            rows = validate_journal_hash_chain(journal)
            assert_no_pending_start(rows)
            control_hash, preflight_hash = existing_packet_hashes(packet)
            completed = validate_resume_prefix(packet, ledger_path, rows)
        else:
            manifest_path = packet / "control_manifest.json"
            preflight_path = packet / "preflight.json"
            write_once_json(manifest_path, control_manifest(fixtures, claude))
            write_once_json(preflight_path, safe_preflight_metadata(preflight))
            control_hash = file_digest(manifest_path)
            preflight_hash = file_digest(preflight_path)
            completed = []
            ledger = {
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "max_invocations": MAX_INVOCATIONS,
                "source_sha": git_head_sha(),
                "fixture_revision": validate_fixtures(fixtures)["fixture_revision"],
                "launch_controls": launch_controls(fixtures),
                "invocations": [],
                "release_proof_mode": "strict-immutable-v1",
                "control_manifest": "control_manifest.json",
                "control_manifest_digest": control_hash,
                "preflight": "preflight.json",
                "preflight_digest": preflight_hash,
                "event_journal": "events.jsonl",
            }
            ledger_path.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        ledger = load_json(ledger_path)
        manifest = load_packet_sidecar(packet, ledger["control_manifest"], control_hash, "control manifest")
        current_preflight = load_packet_sidecar(packet, ledger["preflight"], preflight_hash, "first preflight")
        require(current_preflight.get("checked_before_first_invocation") is True, "preflight was overwritten or was not first-call metadata")
        require(current_preflight.get("secrets_stored") is False, "preflight stores secrets; refusing to spawn")
        require(manifest.get("source_head") == git_head_sha(), "source drift before invocation")
        require(manifest.get("runner_code_digest") == file_digest(Path(__file__).resolve()), "runner/evaluator drift before invocation")
        require(manifest.get("fixture_file_digests") == fixture_file_digests(fixtures), "fixture drift before invocation")

        session_ids: dict[str, str] = {}
        for item in ledger.get("invocations", []):
            artifact_path = packet / item["artifact"]
            session_id = artifact_result(load_json(artifact_path)).get("session_id")
            if isinstance(session_id, str):
                session_ids[item["slot"]] = session_id

        for slot in EXPECTED_SLOT_ORDER[len(completed) :]:
            predecessor = ACTUAL_RESUME_PREDECESSOR.get(slot)
            resume_id = session_ids.get(predecessor) if predecessor else None
            command = build_command(slot, fixtures, claude=claude, resume_id=resume_id)
            append_journal_event(journal, {
                "event": "invocation_start",
                "slot": slot,
                "source_head": manifest["source_head"],
                "control_manifest_digest": control_hash,
                "preflight_digest": preflight_hash,
                "command_digest": command["command_digest"],
                "timeout_seconds": command["timeout_seconds"],
                "budget_usd": MAX_BUDGET_USD,
            })
            raw_dir = packet / "artifacts" / "raw" / slot
            raw_dir.mkdir(parents=True, exist_ok=True)
            started = time.monotonic()
            timed_out = False
            try:
                proc = subprocess.run(command["argv"], input=command["stdin_prompt"], cwd=command["cwd"], text=True, capture_output=True, timeout=command["timeout_seconds"], check=False)
                exit_status = proc.returncode
                stdout = proc.stdout
                stderr = proc.stderr
            except subprocess.TimeoutExpired as exc:
                timed_out = True
                exit_status = 124
                stdout = exc.stdout if isinstance(exc.stdout, str) else ""
                stderr = exc.stderr if isinstance(exc.stderr, str) else "timeout expired"
            elapsed_ms = int((time.monotonic() - started) * 1000)
            wrapper, result = parse_stdout_wrapper(stdout)
            budget_capped = budget_capped_from_explicit_evidence(exit_status, timed_out, wrapper, stderr)
            write_once(raw_dir / "stdout.txt", stdout.encode("utf-8"))
            write_once(raw_dir / "stderr.txt", stderr.encode("utf-8"))
            write_once_json(raw_dir / "wrapper.json", wrapper)
            write_once_json(raw_dir / "exit.json", {"exit_status": exit_status, "timed_out": timed_out, "budget_capped": budget_capped})
            write_once_json(raw_dir / "timing.json", {"elapsed_ms": elapsed_ms})
            raw_digests = {name: file_digest(raw_dir / name) for name in ("stdout.txt", "stderr.txt", "wrapper.json", "exit.json", "timing.json")}
            artifact = {"slot": slot, "result": result, "wrapper": wrapper, "exit_status": exit_status, "timed_out": timed_out, "budget_capped": budget_capped, "metrics": {"elapsed_ms": elapsed_ms}}
            artifact_path = packet / "artifacts" / "normalized" / f"{slot}.json"
            write_once_json(artifact_path, artifact)
            invocation = {
                "slot": slot,
                "artifact": relpath(artifact_path, packet),
                "raw_dir": relpath(raw_dir, packet),
                "raw_artifact_digests": raw_digests,
                "artifact_digest": file_digest(artifact_path),
                "started_at": "write-once-journal",
                "ended_at": "write-once-journal",
                "exit_status": exit_status,
                "timed_out": timed_out,
                "budget_capped": budget_capped,
                "command_digest": command["command_digest"],
                "command": command,
            }
            if resume_id:
                invocation["resume_from_session_id"] = resume_id
            ledger["invocations"].append(invocation)
            ledger_path.write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            append_journal_event(journal, {"event": "invocation_complete", "slot": slot, "artifact_digest": invocation["artifact_digest"], "raw_artifact_digests": raw_digests, "exit_status": exit_status, "timed_out": timed_out, "budget_capped": budget_capped})
            result_session_id = artifact_result(artifact).get("session_id")
            if isinstance(result_session_id, str):
                session_ids[slot] = result_session_id
            if stop_after_slot == slot:
                break
        return {"packet": str(packet), "ledger": str(ledger_path), "invocations": len(load_json(ledger_path).get("invocations", []))}
    finally:
        try:
            lock.unlink()
        except FileNotFoundError:
            pass


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
    if isinstance(ledger, dict) and ledger.get("release_proof_mode") == "strict-immutable-v1":
        strict = validate_strict_packet(path, fixtures)
        result = validate_ledger(path, fixtures)
        successes = set(result["successes"])
        missing = sorted(REQUIRED_SUCCESS_SLOTS - successes)
        require(not missing, f"proof incomplete; missing successful slots: {missing}")
        require(not result["failed_evidence_slots"], f"proof incomplete; failed evidence slots are not release proof: {result['failed_evidence_slots']}")
        return {**result, **strict, "proof_complete": True}
    if isinstance(ledger, dict) and ledger.get("release_proof_mode") != "strict-immutable-v1":
        raise PacketUnproven("legacy/current mutable packet is informal/non-strict; strict release proof requires immutable control/preflight/raw/journal sidecars")
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


def expect_proof_error(label: str, fn: Any) -> None:
    try:
        fn()
    except ProofError:
        return
    raise ProofError(f"integrity failure did not fail closed: {label}")


def write_fake_claude(path: Path) -> None:
    script = r'''#!/usr/bin/env python3
import json
import os
import re
import sys
from pathlib import Path

marker = os.environ.get("FAKE_CLAUDE_MARKER")
if marker:
    with open(marker, "a", encoding="utf-8") as handle:
        handle.write("spawned\n")
prompt = sys.stdin.read()
match = re.search(r"fixture ([BC][1-5])", prompt)
slot = match.group(1) if match else "B1"
fixture = None
argv = sys.argv[1:]
for idx, item in enumerate(argv):
    if item == "--add-dir" and idx + 1 < len(argv):
        fixture = Path(argv[idx + 1])
        break
if fixture is None:
    print(json.dumps({"error": "missing --add-dir"}))
    sys.exit(2)
artifact = json.loads((fixture / "artifacts" / f"{slot}-ok.json").read_text())
result = artifact["result"]
if slot == "B3":
    result = dict(result)
    result["summary"] = "Successful output discusses budget, max, and cap concepts without a terminal budget error."
print(json.dumps({"type": "result", "session_id": result.get("session_id", f"sess-{slot.lower()}"), "result": result}))
'''
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)


def validate_runner_contract() -> dict[str, Any]:
    """Deterministic fake-Claude tests for immutable strict proof packet semantics."""
    cases: list[str] = []
    with tempfile.TemporaryDirectory(prefix="claude-proof-contract-") as td:
        root = Path(td)
        fake = root / "fake_claude.py"
        write_fake_claude(fake)
        clean = root / "clean"
        run_packet(clean, DEFAULT_FIXTURE_DIR, fake, {"provider": "fake-claude", "checked_before_first_invocation": True, "secrets_stored": False})
        validate_proof_complete(clean / "ledger.json")
        ledger = load_json(clean / "ledger.json")
        require(len(ledger["invocations"]) == MAX_INVOCATIONS, "clean fake packet must invoke exactly ten slots")
        require(ledger["invocations"][2]["budget_capped"] is False, "successful B3 budget/max/cap words must not be a budget cap")
        require(ledger["invocations"][4].get("resume_from_session_id") == "sess-b4", "B5 must record actual resume lineage from B4")
        require(ledger["invocations"][9].get("resume_from_session_id") == "sess-c4", "C5 must record actual resume lineage from C4")
        cases.append("clean full packet")
        cases.append("successful output containing budget words")
        cases.append("actual resume lineage")

        partial = root / "partial"
        run_packet(partial, DEFAULT_FIXTURE_DIR, fake, stop_after_slot="B3")
        expect_proof_error("terminal/interruption after B3", lambda: validate_proof_complete(partial / "ledger.json"))
        cases.append("terminal/interruption after B3")
        append_journal_event(partial / "events.jsonl", {"event": "invocation_start", "slot": "B4", "source_head": git_head_sha(), "control_manifest_digest": load_json(partial / "ledger.json")["control_manifest_digest"], "preflight_digest": load_json(partial / "ledger.json")["preflight_digest"], "command_digest": "pending", "timeout_seconds": TIMEOUT_SECONDS, "budget_usd": MAX_BUDGET_USD})
        expect_proof_error("pending-start recovery", lambda: run_packet(partial, DEFAULT_FIXTURE_DIR, fake))
        cases.append("pending-start recovery")

        overlap = root / "overlap"
        run_packet(overlap, DEFAULT_FIXTURE_DIR, fake)
        rows = read_jsonl(overlap / "events.jsonl")
        rows = [rows[0], rows[2], rows[1], *rows[3:]]
        rewrite_journal_hash_chain(overlap / "events.jsonl", rows)
        expect_proof_error("overlapping/all-starts-before-completions event order", lambda: validate_proof_complete(overlap / "ledger.json"))
        cases.append("overlapping start-complete order")

        command_drift = root / "command-drift"
        run_packet(command_drift, DEFAULT_FIXTURE_DIR, fake)
        ledger = load_json(command_drift / "ledger.json")
        ledger["invocations"][0]["command"]["argv"][0] = "/tmp/unreviewed-claude"
        drift_digest = command_digest_from_argv(ledger["invocations"][0]["command"]["argv"])
        ledger["invocations"][0]["command_digest"] = drift_digest
        rows = read_jsonl(command_drift / "events.jsonl")
        rows[0]["command_digest"] = drift_digest
        rewrite_journal_hash_chain(command_drift / "events.jsonl", rows)
        (command_drift / "ledger.json").write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        expect_proof_error("bad command digest and argv", lambda: validate_proof_complete(command_drift / "ledger.json"))
        cases.append("command bound to immutable control manifest")

        invalid_preflight = root / "invalid-preflight"
        marker = root / "invalid-preflight-spawned.txt"
        previous_marker = os.environ.get("FAKE_CLAUDE_MARKER")
        os.environ["FAKE_CLAUDE_MARKER"] = str(marker)
        try:
            expect_proof_error("invalid preflight metadata before spawn", lambda: run_packet(invalid_preflight, DEFAULT_FIXTURE_DIR, fake, {"provider": "fake-claude", "checked_before_first_invocation": True, "secrets_stored": True}))
        finally:
            if previous_marker is None:
                os.environ.pop("FAKE_CLAUDE_MARKER", None)
            else:
                os.environ["FAKE_CLAUDE_MARKER"] = previous_marker
        require(not marker.exists(), "invalid preflight metadata must fail before spawning fake Claude")
        cases.append("invalid preflight fail-before-spawn")

        missing_preflight = root / "missing-preflight"
        run_packet(missing_preflight, DEFAULT_FIXTURE_DIR, fake)
        (missing_preflight / "preflight.json").unlink()
        expect_proof_error("missing first preflight", lambda: validate_proof_complete(missing_preflight / "ledger.json"))
        cases.append("preflight missing")

        overwritten_preflight = root / "overwritten-preflight"
        run_packet(overwritten_preflight, DEFAULT_FIXTURE_DIR, fake)
        (overwritten_preflight / "preflight.json").write_text(json.dumps({"provider": "fake-claude", "checked_before_first_invocation": False, "secrets_stored": False}), encoding="utf-8")
        expect_proof_error("preflight overwrite", lambda: validate_proof_complete(overwritten_preflight / "ledger.json"))
        cases.append("preflight overwrite")

        control_drift = root / "control-drift"
        run_packet(control_drift, DEFAULT_FIXTURE_DIR, fake)
        manifest = load_json(control_drift / "control_manifest.json")
        manifest["runner_code_digest"] = "0" * 64
        (control_drift / "control_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
        expect_proof_error("mid-envelope detector/normalizer change", lambda: validate_proof_complete(control_drift / "ledger.json"))
        cases.append("mid-envelope detector/normalizer change")

        raw_mutation = root / "raw-mutation"
        run_packet(raw_mutation, DEFAULT_FIXTURE_DIR, fake)
        with (raw_mutation / "artifacts" / "raw" / "B1" / "stdout.txt").open("a", encoding="utf-8") as handle:
            handle.write("\nmutated\n")
        expect_proof_error("raw artifact mutation", lambda: validate_proof_complete(raw_mutation / "ledger.json"))
        cases.append("raw artifact mutation")

        journal_break = root / "journal-break"
        run_packet(journal_break, DEFAULT_FIXTURE_DIR, fake)
        rows = read_jsonl(journal_break / "events.jsonl")
        rows[2]["slot"] = "B9"
        (journal_break / "events.jsonl").write_text("\n".join(json.dumps(row, sort_keys=True, separators=(",", ":")) for row in rows) + "\n", encoding="utf-8")
        expect_proof_error("journal rewrite/hash break", lambda: validate_proof_complete(journal_break / "ledger.json"))
        cases.append("journal rewrite/hash break")

        duplicate = root / "duplicate"
        run_packet(duplicate, DEFAULT_FIXTURE_DIR, fake)
        ledger = load_json(duplicate / "ledger.json")
        ledger["invocations"].append(dict(ledger["invocations"][-1]))
        (duplicate / "ledger.json").write_text(json.dumps(ledger, indent=2, sort_keys=True), encoding="utf-8")
        expect_proof_error("duplicate slot", lambda: validate_proof_complete(duplicate / "ledger.json"))
        cases.append("duplicate slot")

        concurrent = root / "concurrent"
        concurrent.mkdir()
        write_once(concurrent / ".runner.lock", b"held\n")
        expect_proof_error("duplicate/concurrent runner", lambda: run_packet(concurrent, DEFAULT_FIXTURE_DIR, fake))
        cases.append("duplicate/concurrent runner")

        source_drift = root / "source-drift"
        run_packet(source_drift, DEFAULT_FIXTURE_DIR, fake)
        manifest = load_json(source_drift / "control_manifest.json")
        manifest["fixture_file_digests"]["prompt_B1.txt"] = "0" * 64
        (source_drift / "control_manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8")
        expect_proof_error("source/control drift", lambda: validate_proof_complete(source_drift / "ledger.json"))
        cases.append("source/control drift")

        correction = root / "correction"
        run_packet(correction, DEFAULT_FIXTURE_DIR, fake)
        append_journal_event(correction / "events.jsonl", {"event": "correction", "slot": "B1", "before_digest": "a", "after_digest": "b"})
        expect_proof_error("correction after first call", lambda: validate_proof_complete(correction / "ledger.json"))
        cases.append("correction after first call")

        ledger_behind = root / "ledger-behind-journal"
        run_packet(ledger_behind, DEFAULT_FIXTURE_DIR, fake, stop_after_slot="B2")
        ledger = load_json(ledger_behind / "ledger.json")
        ledger["invocations"] = ledger["invocations"][:1]
        (ledger_behind / "ledger.json").write_text(json.dumps(ledger, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        marker = root / "ledger-behind-spawned.txt"
        previous_marker = os.environ.get("FAKE_CLAUDE_MARKER")
        os.environ["FAKE_CLAUDE_MARKER"] = str(marker)
        try:
            expect_proof_error("ledger behind immutable journal/raw evidence", lambda: run_packet(ledger_behind, DEFAULT_FIXTURE_DIR, fake))
        finally:
            if previous_marker is None:
                os.environ.pop("FAKE_CLAUDE_MARKER", None)
            else:
                os.environ["FAKE_CLAUDE_MARKER"] = previous_marker
        require(not marker.exists(), "ledger-behind-journal resume must fail before spawning fake Claude")
        cases.append("ledger behind journal/raw resume fail-before-spawn")

    return {"runner_contract_cases": cases, "model_calls": 0}


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
    runner = sub.add_parser("run-packet")
    runner.add_argument("packet_dir")
    runner.add_argument("--claude", default=str(DEFAULT_CLAUDE))
    runner.add_argument("--preflight-json")
    runner.add_argument("--stop-after-slot")
    sub.add_parser("validate-runner-contract")
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
        elif args.cmd == "run-packet":
            preflight = json.loads(args.preflight_json) if args.preflight_json else None
            result = run_packet(Path(args.packet_dir).resolve(), fixtures, Path(args.claude).resolve(), preflight, stop_after_slot=args.stop_after_slot)
        elif args.cmd == "validate-runner-contract":
            result = validate_runner_contract()
        else:  # pragma: no cover
            raise AssertionError(args.cmd)
    except ProofError as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

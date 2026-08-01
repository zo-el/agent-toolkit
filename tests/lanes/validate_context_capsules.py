#!/usr/bin/env python3
"""Validate Release A Slice 1 context capsule fixtures.

The repo intentionally keeps this stdlib-only. The JSON Schema documents the
portable shape; this runner enforces cross-field/source-of-truth invariants that
matter for the platform-keyed capsule contract.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

LANE_LABEL_RE = re.compile(r"^#([1-9][0-9]*) .+")
FORBIDDEN_CANONICAL_KEYS = {
    "lane_subject",
    "status",
    "dependencies",
    "owner",
    "assignee",
    "task_tool_status",
    "task_tool_dependencies",
    "task_tool_owner",
    "restore_subject",
    "restore_status",
    "restore_dependencies",
    "restore_owner",
    "override_subject",
    "override_status",
    "override_dependencies",
    "override_owner",
}
ALLOWED_CANONICAL_SNAPSHOT_PATH = ("platform_identity", "canonical_snapshot")


class CapsuleError(Exception):
    pass


def fail(errors: list[str], path: str, message: str) -> None:
    errors.append(f"{path}: {message}")


def require_obj(errors: list[str], value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        fail(errors, path, "must be an object")
        return {}
    return value


def require_list(errors: list[str], value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        fail(errors, path, "must be a list")
        return []
    return value


def require_str(errors: list[str], value: Any, path: str) -> str:
    if not isinstance(value, str) or not value:
        fail(errors, path, "must be a non-empty string")
        return ""
    return value


def require_bool(errors: list[str], value: Any, path: str) -> bool:
    if not isinstance(value, bool):
        fail(errors, path, "must be a boolean")
        return False
    return value


def lane_number_from_label(label: str) -> int | None:
    match = LANE_LABEL_RE.match(label)
    if not match:
        return None
    return int(match.group(1))


def validate_lane_ref(errors: list[str], ref: Any, path: str) -> None:
    obj = require_obj(errors, ref, path)
    number = obj.get("lane_number")
    label = require_str(errors, obj.get("lane_label"), f"{path}.lane_label")
    if not isinstance(number, int) or number < 1:
        fail(errors, f"{path}.lane_number", "must be a positive integer")
        return
    label_number = lane_number_from_label(label)
    if label_number is None:
        fail(errors, f"{path}.lane_label", "must begin with '#N '")
    elif label_number != number:
        fail(errors, path, f"lane_number {number} does not match label #{label_number}")


def validate_no_canonical_overrides(errors: list[str], value: Any, path: tuple[str, ...] = ()) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = path + (key,)
            assumption_status = len(path) == 3 and path[0] == "lane_local" and path[1] == "assumptions" and key == "status"
            if key in FORBIDDEN_CANONICAL_KEYS and path != ALLOWED_CANONICAL_SNAPSHOT_PATH and not assumption_status:
                fail(errors, ".".join(child_path), "canonical platform lane truth may appear only in platform_identity.canonical_snapshot")
            validate_no_canonical_overrides(errors, child, child_path)
    elif isinstance(value, list):
        for idx, child in enumerate(value):
            validate_no_canonical_overrides(errors, child, path + (str(idx),))


def validate_platform_identity(errors: list[str], capsule: dict[str, Any]) -> None:
    platform = require_obj(errors, capsule.get("platform_identity"), "platform_identity")
    for key in ("task_tool", "platform_task_id", "platform_lane_id", "source_session_id"):
        require_str(errors, platform.get(key), f"platform_identity.{key}")
    snapshot = require_obj(errors, platform.get("canonical_snapshot"), "platform_identity.canonical_snapshot")
    label = require_str(errors, snapshot.get("lane_subject"), "platform_identity.canonical_snapshot.lane_subject")
    lane_identity = require_obj(errors, capsule.get("lane_identity"), "lane_identity")
    lane_number = lane_identity.get("lane_number")
    label_number = lane_number_from_label(label)
    if label_number is None:
        fail(errors, "platform_identity.canonical_snapshot.lane_subject", "must begin with '#N '")
    elif lane_number != label_number:
        fail(errors, "platform_identity.canonical_snapshot", "snapshot lane_subject must match lane_identity.lane_number")
    require_str(errors, snapshot.get("status"), "platform_identity.canonical_snapshot.status")
    require_list(errors, snapshot.get("dependencies"), "platform_identity.canonical_snapshot.dependencies")
    require_str(errors, snapshot.get("snapshot_at"), "platform_identity.canonical_snapshot.snapshot_at")
    require_str(errors, snapshot.get("source_revision"), "platform_identity.canonical_snapshot.source_revision")
    for idx, dep in enumerate(snapshot.get("dependencies", [])):
        validate_lane_ref(errors, dep, f"platform_identity.canonical_snapshot.dependencies[{idx}]")


def validate_fallback_identity(errors: list[str], capsule: dict[str, Any]) -> None:
    fallback = require_obj(errors, capsule.get("fallback_identity"), "fallback_identity")
    require_str(errors, fallback.get("fallback_lane_id"), "fallback_identity.fallback_lane_id")
    if fallback.get("fallback_reason") != "task_tools_absent":
        fail(errors, "fallback_identity.fallback_reason", "must be task_tools_absent")
    if fallback.get("reduced_fidelity") is not True:
        fail(errors, "fallback_identity.reduced_fidelity", "must be true")
    if fallback.get("non_platform_persisted") is not True:
        fail(errors, "fallback_identity.non_platform_persisted", "must be true")


def validate_cross_lane_reference(errors: list[str], ref: Any, path: str) -> None:
    obj = require_obj(errors, ref, path)
    validate_lane_ref(errors, obj.get("source_lane"), f"{path}.source_lane")
    require_str(errors, obj.get("reason"), f"{path}.reason")
    evidence = require_list(errors, obj.get("evidence_refs"), f"{path}.evidence_refs")
    if not evidence:
        fail(errors, f"{path}.evidence_refs", "must include explicit evidence")
    if obj.get("confidence") not in {"low", "medium", "high"}:
        fail(errors, f"{path}.confidence", "must be low, medium, or high")


def validate_lane_local(errors: list[str], capsule: dict[str, Any]) -> None:
    lane_local = require_obj(errors, capsule.get("lane_local"), "lane_local")
    for key in ("facts", "assumptions", "decisions", "evidence", "blockers", "recovery_notes"):
        require_list(errors, lane_local.get(key), f"lane_local.{key}")
    next_action = require_obj(errors, lane_local.get("next_proposed_action"), "lane_local.next_proposed_action")
    require_str(errors, next_action.get("summary"), "lane_local.next_proposed_action.summary")
    mutation_risk = next_action.get("mutation_risk")
    if mutation_risk not in {"none", "local", "external"}:
        fail(errors, "lane_local.next_proposed_action.mutation_risk", "must be none, local, or external")
    requires_fresh = require_bool(errors, next_action.get("requires_fresh_platform_read"), "lane_local.next_proposed_action.requires_fresh_platform_read")
    freshness_checked = require_bool(errors, next_action.get("freshness_checked"), "lane_local.next_proposed_action.freshness_checked")
    if mutation_risk in {"local", "external"} and requires_fresh and not freshness_checked:
        fail(errors, "lane_local.next_proposed_action", "mutating stale action requires a fresh platform/source revision check")
    if freshness_checked and not next_action.get("freshness_evidence_refs"):
        fail(errors, "lane_local.next_proposed_action.freshness_evidence_refs", "freshness_checked requires evidence refs")

    global_refs = capsule.get("cross_lane_references", [])
    for idx, ref in enumerate(global_refs):
        validate_cross_lane_reference(errors, ref, f"cross_lane_references[{idx}]")

    for idx, decision in enumerate(lane_local.get("decisions", [])):
        obj = require_obj(errors, decision, f"lane_local.decisions[{idx}]")
        uses_cross_lane = require_bool(errors, obj.get("uses_cross_lane_facts"), f"lane_local.decisions[{idx}].uses_cross_lane_facts")
        decision_refs = obj.get("cross_lane_refs", [])
        if uses_cross_lane and not decision_refs and not global_refs:
            fail(errors, f"lane_local.decisions[{idx}]", "cross-lane facts require explicit provenance")
        for ref_idx, ref in enumerate(decision_refs):
            validate_cross_lane_reference(errors, ref, f"lane_local.decisions[{idx}].cross_lane_refs[{ref_idx}]")

    active_conflicts: dict[str, int] = {}
    for assumption in lane_local.get("assumptions", []):
        obj = require_obj(errors, assumption, "lane_local.assumptions[]")
        group = obj.get("conflict_group")
        if group and obj.get("status", "active") == "active":
            active_conflicts[group] = active_conflicts.get(group, 0) + 1
    has_conflict_blocker = any(
        isinstance(blocker, dict) and blocker.get("kind") in {"conflict", "stale_context"}
        for blocker in lane_local.get("blockers", [])
    )
    if mutation_risk in {"local", "external"} and any(count > 1 for count in active_conflicts.values()) and not has_conflict_blocker:
        fail(errors, "lane_local.assumptions", "active conflicting assumptions require a visible blocker before mutation")


def validate_capsule(capsule: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if capsule.get("schema_version") != "context-capsule/v1":
        fail(errors, "schema_version", "must be context-capsule/v1")
    require_str(errors, capsule.get("record_id"), "record_id")
    provenance = require_obj(errors, capsule.get("provenance"), "provenance")
    task_tools = provenance.get("task_tools")
    if task_tools not in {"present", "absent"}:
        fail(errors, "provenance.task_tools", "must be present or absent")
    require_str(errors, provenance.get("capture_source"), "provenance.capture_source")
    require_str(errors, provenance.get("captured_at"), "provenance.captured_at")

    validate_lane_ref(errors, capsule.get("lane_identity"), "lane_identity")
    validate_no_canonical_overrides(errors, capsule)

    if task_tools == "present":
        if "fallback_identity" in capsule:
            fail(errors, "fallback_identity", "forbidden when task tools are present")
        if "platform_identity" not in capsule:
            fail(errors, "platform_identity", "required when task tools are present")
        if not provenance.get("source_revision"):
            fail(errors, "provenance.source_revision", "required when task tools are present")
        validate_platform_identity(errors, capsule)
    elif task_tools == "absent":
        if "platform_identity" in capsule:
            fail(errors, "platform_identity", "forbidden when task tools are absent")
        if "fallback_identity" not in capsule:
            fail(errors, "fallback_identity", "required when task tools are absent")
        validate_fallback_identity(errors, capsule)

    validate_lane_local(errors, capsule)
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expect-invalid", action="store_true", help="Pass only if every file is rejected")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args()

    failures = 0
    for raw_path in args.paths:
        path = Path(raw_path)
        try:
            capsule = json.loads(path.read_text())
        except Exception as exc:  # noqa: BLE001 - report fixture load errors cleanly
            errors = [f"load: {exc}"]
        else:
            if not isinstance(capsule, dict):
                errors = ["root: must be an object"]
            else:
                errors = validate_capsule(capsule)

        valid = not errors
        if args.expect_invalid:
            if valid:
                print(f"FAIL {path}: expected invalid but passed")
                failures += 1
            else:
                print(f"ok invalid {path}: {errors[0]}")
        else:
            if valid:
                print(f"ok valid {path}")
            else:
                print(f"FAIL {path}:")
                for error in errors:
                    print(f"  - {error}")
                failures += 1
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

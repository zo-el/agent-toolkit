#!/usr/bin/env python3
"""Check the published Draft 2020-12 context-capsule schema against fixtures."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

try:
    import jsonschema
except Exception as exc:  # noqa: BLE001 - executable test should name missing dependency
    print(f"FAIL: jsonschema package unavailable: {exc}", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[2]
SCHEMA = ROOT / "orchestration" / "context-capsule.schema.json"
VALID_FIXTURES = [
    ROOT / "orchestration/examples/context-capsule.valid.json",
    ROOT / "orchestration/examples/context-capsule.task-tools-absent.json",
    ROOT / "tests/fixtures/context-capsules/valid-platform.json",
    ROOT / "tests/fixtures/context-capsules/valid-task-tools-absent.json",
]
INVALID_FIXTURES = [
    ROOT / "tests/fixtures/context-capsules/invalid-mismatched-lane-number.json",
    ROOT / "tests/fixtures/context-capsules/invalid-missing-number-prefix.json",
    ROOT / "tests/fixtures/context-capsules/invalid-supplemental-status-override.json",
    ROOT / "tests/fixtures/context-capsules/invalid-cross-lane-without-provenance.json",
    ROOT / "tests/fixtures/context-capsules/invalid-stale-mutating-action.json",
    ROOT / "tests/fixtures/context-capsules/invalid-fallback-masquerade.json",
    ROOT / "tests/fixtures/context-capsules/invalid-conflicting-assumptions-without-blocker.json",
]


def load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def errors_for(validator: jsonschema.Draft202012Validator, path: Path) -> list[jsonschema.ValidationError]:
    return sorted(validator.iter_errors(load(path)), key=lambda err: list(err.path))


def main() -> int:
    schema = load(SCHEMA)
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema)
    failures: list[str] = []

    for path in VALID_FIXTURES:
        errors = errors_for(validator, path)
        if errors:
            failures.append(f"valid fixture rejected by schema: {path.relative_to(ROOT)}: {errors[0].message}")

    for path in INVALID_FIXTURES:
        errors = errors_for(validator, path)
        if not errors:
            failures.append(f"negative fixture accepted by schema: {path.relative_to(ROOT)}")

    if failures:
        print("FAIL context-capsule-schema parity", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("ok context-capsule-schema parity")
    return 0


if __name__ == "__main__":
    sys.exit(main())

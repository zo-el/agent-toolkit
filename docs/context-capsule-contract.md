# Platform-keyed context capsule contract

Release A Slice 1 adds a context/provenance capsule record for multi-lane orchestration. The capsule is supplemental. It is keyed to a platform task/lane identity when task tools are available, and it never becomes the source of truth for the visible lane/list.

## Boundary

When task tools are present, the platform task lane is canonical for live lane subject, status, dependencies, owner, and assignee. A capsule may include `platform_identity.canonical_snapshot` of those fields only as a freshness/evidence input. Consumers must re-read platform task state before acting on live lane truth and must reject capsule records that try to duplicate, override, project, or restore a different subject/status/dependency/owner truth.

When task tools are absent, a lower-fidelity fallback record is allowed only if it is clearly labeled:

- `provenance.task_tools: "absent"`
- `fallback_identity.fallback_reason: "task_tools_absent"`
- `fallback_identity.reduced_fidelity: true`
- `fallback_identity.non_platform_persisted: true`

Fallback records are not platform-persisted lanes and cannot masquerade as normal platform-keyed capsules.

## Required capsule areas

- `provenance`: task-tool availability, capture source, timestamp, and source revision when platform tools are present.
- `platform_identity`: platform task/lane id, source session, and freshness-only canonical snapshot when task tools are present.
- `fallback_identity`: only for `task_tools_absent` records.
- `lane_identity`: lane number plus user-visible `#N ` label; the number in the label must match `lane_number`.
- `lane_local`: facts, assumptions, decisions, evidence, blockers/details, recovery notes, and next proposed action.
- `cross_lane_references`: explicit source lane, reason, evidence, and confidence for any cross-lane fact used in a decision.

## Validation behavior

The schema in `orchestration/context-capsule.schema.json` documents the shape. The executable validator in `tests/lanes/validate_context_capsules.py` enforces semantic invariants that plain JSON Schema cannot express without extra dependencies:

- valid platform-keyed capsules pass;
- valid task-tools-absent fallback capsules pass only in reduced-fidelity form;
- malformed platform/fallback provenance is rejected;
- missing or mismatched `#N ` lane identity is rejected;
- supplemental status/dependency/owner override keys are rejected outside `platform_identity.canonical_snapshot`;
- decisions using cross-lane facts require explicit provenance links;
- stale/mutating next actions require a fresh platform/source revision check;
- active conflicting assumptions require a visible conflict/stale blocker before mutation.

Run:

```bash
python3 tests/lanes/validate_context_capsules.py tests/fixtures/context-capsules/valid-platform.json
python3 tests/lanes/validate_context_capsules.py --expect-invalid tests/fixtures/context-capsules/invalid-*.json
./tests/run.sh
```

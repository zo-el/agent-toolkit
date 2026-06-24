---
name: plannotator-loop
description: Iterative review of a plan, spec, task, or other document via Plannotator — open the artifact, address every annotation, reopen, repeat until a round returns clean. Use when the user wants to review or iterate on a document, asks for back-and-forth feedback rounds, or right after you produce a substantial spec/plan/task.
---

# Plannotator review loop

Drive document review through Plannotator rounds instead of inline chat review.

## The loop

1. `plannotator annotate <absolute-path>` (background is fine — pick up the output when the session closes). Never ask the user to run it themselves.
2. **Address every annotation**, not just edit the line it points at:
   - Fix the artifact under review.
   - **Ripple the decision** into every affected sibling doc (specs, diagrams, error tables, naming) in the same round; grep for stale terms the change leaves behind.
   - If an annotation questions a fact, **verify against the actual code** before answering — an annotation is often a real gap, not a doc nit.
3. Reopen the artifact for the next round.
4. A round that returns **no feedback** ends the loop — say so briefly; confirm with the user before flipping the artifact's status (closing the tab is not approval).

## Codify recurring feedback

- When an annotation expresses a **pattern** (how docs should look, how AC should be written, how tests should be structured) rather than a one-off fix: apply it everywhere it applies now, **and** add the rule to its durable home (workflow doc, the relevant skill, the repo's AGENTS.md) so it never has to be given again. Tell the user where it was codified.
- When it expresses a one-off decision: apply it and move on.

## Summarize each round

After addressing a round, report: what each annotation changed, anything it revealed beyond the doc (real code gaps, design caveats), and what was codified where.

---
name: godot-logic-review
description: Review Godot RTS logic against project specs and report evidence-backed findings.
---

# Godot Logic Review

Perform a read-only review of requested gameplay or supporting code in this Godot RTS repository. Look for concrete ways the implementation can violate intended behavior, state invariants, or required acceptance conditions. Do not refactor or fix the code during a review unless the user separately asks for that work.

## Review method

1. Read `Documents/DEVELOPMENT_WORKFLOW.md` and the relevant normative specifications. Consult `Documents/ACCEPTANCE_TESTS.md` for required cases; treat provisional cases as proposals, not pass/fail rules. Read `Documents/GAME_DESIGN.md` if purpose or document precedence is unclear.
2. Inspect the changed code and enough callers, state transitions, and data definitions to follow the behavior. Check actual execution paths instead of judging names or isolated snippets.
3. Trace each relevant requirement into the implementation. Focus on command/state separation, waypoint and anchor lifecycle, single ownership of position updates, mode-specific permissions, failure/recovery behavior, and edge conditions when they apply.
4. Distinguish a demonstrated defect from a possible risk, a missing requirement, and a spec gap. Never report an unresolved design choice as a bug merely because one implementation choice was selected.
5. If runtime behavior or a relevant acceptance condition cannot be established from source, use available project tooling only when appropriate and safe. State the boundary of evidence; do not imply source inspection proves runtime correctness.

## Findings

- Lead with findings, ordered by severity: broken required behavior or data corruption first, then narrower correctness issues. Omit generic style commentary and speculative findings without a plausible execution path.
- For each finding, give severity, file and line, the triggering scenario, the observed code path, and the violated specification or acceptance case. Explain the user-visible consequence.
- If there are no actionable findings, say so and summarize what was reviewed and what could not be verified.
- Do not broaden the review into performance analysis unless requested; use the performance-review workflow for measurement and scaling concerns.

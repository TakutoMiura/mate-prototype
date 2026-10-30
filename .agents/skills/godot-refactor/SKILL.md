---
name: godot-refactor
description: Refactor Godot RTS code from review findings while preserving specified behavior.
---

# Godot Refactor

Use this skill when the user asks to address findings from a logic review, a performance review, or both. The outcome is simpler or faster implementation with the required gameplay behavior preserved. A review finding is evidence to investigate, not permission to alter unresolved game design.

## Plan from findings

1. Read `Documents/DEVELOPMENT_WORKFLOW.md`, the relevant specifications, affected acceptance cases, and the review findings. Inspect the current code because the review may be stale or based on a different revision.
2. Map every accepted finding to the responsible code and expected behavior. Confirm that each finding is reproducible or still applicable before changing it.
3. If addressing a finding requires choosing a `[未決]` rule, changing a required behavior, or making an undocumented product tradeoff, stop that dependent change and ask the user. Continue independent, behavior-preserving cleanup if useful.
4. Prefer a small refactor that makes ownership and state transitions clearer or removes the measured bottleneck without changing externally visible behavior. Avoid broad rewrites and speculative optimization.

## Preserve and verify

- Preserve the relevant required acceptance behavior before and after the refactor. For performance work, retain correctness first and compare the same workload and environment used in the review when available.
- Use existing tests or acceptance procedures where available. Add or run checks only when requested or needed to verify the refactor; do not describe unrun checks as passing.
- Revisit each finding after the change. Report whether it is resolved, remains, or could not be verified, and identify any new tradeoff or deferred decision.
- Keep the diff focused. Update specifications or acceptance cases only when the user has made a design decision or the existing document is objectively inconsistent with an already agreed behavior.

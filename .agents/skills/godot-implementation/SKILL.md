---
name: godot-implementation
description: Implement this Godot RTS from project specs; ask before choosing unresolved gameplay rules.
---

# Godot Implementation

Implement a requested game change in this repository while preserving the behavior defined by its specifications. Apply this skill to Godot gameplay, input, movement, AI, UI, project configuration, and related implementation work.

## Before changing code

1. Read `Documents/DEVELOPMENT_WORKFLOW.md` and `README.md` for repository conventions.
2. Read the relevant normative specifications: `Documents/SQUAD_BEHAVIOR.md` for command and combat states, `Documents/MOVEMENT_SPEC.md` for movement and pathing, and `Documents/INPUT_SPEC.md` for controls. Read `Documents/GAME_DESIGN.md` for project intent and `Documents/ACCEPTANCE_TESTS.md` for applicable required and provisional cases.
3. Trace the existing code and project structure before choosing where a change belongs. Do not treat current behavior as the intended design when it conflicts with the documents.
4. Separate confirmed requirements from proposals, provisional cases, and unresolved decisions. Do not silently turn an unresolved rule, threshold, default, input binding, or exception into a design decision.

## Resolve specification gaps

- If a needed behavior depends on a `[未決]` item, a conflict between documents, or an acceptance case marked provisional, explain the concrete choice that blocks implementation and ask the user to decide before implementing that behavior.
- Continue independent work that does not depend on the unresolved decision. Keep the change reviewable and clearly identify any deliberately deferred part.
- Do not invent a numerical default to make the feature appear complete. If the specification explicitly calls a value a tunable parameter but gives no value, ask how it should be initialized before behavior depends on it.
- When a product decision is made, update the responsible specification and affected acceptance conditions in the same change when appropriate; preserve the status labels and distinguish the decision from remaining proposals.

## Implement and report

- Keep responsibilities aligned with the specifications: squad command/state, action decisions, path planning, and movement execution should not compete to write a unit's position. Reuse existing architecture when it meets that contract; avoid adding abstractions without a concrete need.
- Implement the smallest coherent change that satisfies the confirmed scope. Keep behavior deterministic where possible and expose only those tuning parameters supported by the specification.
- Verify the change with checks appropriate to the request and available project setup. Do not claim runtime behavior was verified if only source inspection or static checks were performed. If a relevant acceptance case cannot be exercised, state that limitation and its cause.
- In the final report, summarize the behavior changed, the specifications or acceptance cases addressed, verification actually performed, and any decision that still needs the user's input.

---
name: godot-performance-review
description: Measure Godot RTS performance and report profiler-backed bottlenecks and limits.
---

# Godot Performance Review

Review performance in the context of this RTS project. Prefer measured evidence from a representative run to guesses based on code shape. This skill is for performance analysis and recommendations; do not make code changes unless the user also requests fixes or refactoring.

## Establish a meaningful target

1. Read `README.md`, `Documents/DEVELOPMENT_WORKFLOW.md`, and the relevant movement, squad, and game-design specifications. Identify existing project settings, implemented workload, and any documented hardware or unit-count targets.
2. Determine whether there is enough implementation and a runnable project to measure. If not, provide a bounded static risk review and state that measured performance is not yet available.
3. Use an existing target workload or documented acceptance map when available. If the result depends on unspecified hardware, frame-rate, unit-count, resolution, or quality targets, ask for the missing target rather than inventing a pass threshold. You may still report measurements with their exact environment and workload.

## Gather evidence

- Prefer Godot's built-in profiler/monitoring and repeatable project runs. Record Godot version, build mode, platform/hardware when known, scene/map, unit count, duration, and relevant profiler counters.
- Examine likely RTS costs only in the paths the project actually implements: per-unit processing, movement and collision, path queries/replanning, allocation churn, signals and scene-tree work, rendering and effects, and data-structure complexity.
- Compare representative workloads or repeated runs when possible. Separate measured bottlenecks from static concerns and expected scaling risks. Do not label an unmeasured code pattern a measured regression.
- Do not add a permanent benchmark framework or change gameplay quality settings solely to manufacture a passing result. If a temporary measurement setup is needed, keep it scoped and disclose it.
- Do not claim a performance target passes without a defined target and evidence collected under a matching workload. If the project cannot be launched or profiled, state the blocker and provide the best source-based assessment instead.

## Report

Summarize the workload and environment first. Then list measured bottlenecks by impact with profiler evidence, affected code paths, and a practical next step. Clearly mark estimates and unverified assumptions. Include the limits of the measurement and the next workload needed to resolve them; do not prescribe an optimization that risks violating required game behavior without naming the tradeoff.

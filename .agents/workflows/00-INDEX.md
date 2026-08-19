---
description: Index of all invokable workflows for the startGOLD mobile brain system
version: 1.0.0
last_updated: 2026-08-19
---

# Workflow Index

Invoke by name (e.g. "run /build-module-brain for sip"). Each workflow file has numbered Steps and a
Completion Report template — follow both.

## Build & Maintain the Brain
| Workflow | Purpose |
|---|---|
| [`build-module-brain`](build-module-brain.md) | Generate/refresh the 8-document brain for one feature module, by reading its actual Dart source. |
| [`build-system-brain`](build-system-brain.md) | Aggregate all module brains into the cross-cutting `_SYSTEM/` docs (danger zones, diagnostic playbook, dependency graph). |
| [`sync-brain`](sync-brain.md) | Re-align an existing brain against code that has drifted since it was built, or port this whole system to another Flutter project. |

## Fix → Test → Learn
| Workflow | Purpose |
|---|---|
| [`fix-single-bug`](fix-single-bug.md) | Routing hub — classifies a bug report and dispatches to the right fix workflow. |
| [`fix-widget-bug`](fix-widget-bug.md) | Fix UI/widget-layer bugs (layout, state binding, navigation, rendering). |
| [`fix-logic-bug`](fix-logic-bug.md) | Fix business-logic/data bugs (calculations, validation, API contract mismatches, security). |
| [`test-and-verify`](test-and-verify.md) | Verify a fix actually works — analyze, run affected widget/unit tests, manual-flow checklist. |
| [`learn-and-improve`](learn-and-improve.md) | Write the fix's learnings back into the relevant brain docs. |
| [`module-bug-audit`](module-bug-audit.md) | Proactive sweep of one module against `DANGER_ZONES.md` and its own `FORENSIC_TEMPLATE.md`. |

## Requirements & Reporting
| Workflow | Purpose |
|---|---|
| [`get-requirement`](get-requirement.md) | Structured intake for a new feature/change request before implementation starts. |
| [`release-checklist`](release-checklist.md) | Pre-release checklist (version bump, native config review, security screens, store metadata). |
| [`sprint-status`](sprint-status.md) | Summarize in-flight work across modules for a status update. |
| [`system-health`](system-health.md) | Snapshot of brain coverage %, staleness, and known open risks across all modules. |
| [`validate-workflows`](validate-workflows.md) | Self-check that every workflow file is well-formed and every `{TOKEN}` resolves in `config.md`. |

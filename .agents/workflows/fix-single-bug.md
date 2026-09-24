---
description: Routing hub — classify a bug report and dispatch to the right fix workflow
version: 1.0.0
last_updated: 2026-08-19
---

# /fix-single-bug

## Purpose
Entry point for any bug fix. Classifies the bug, runs Step Zero (see `AGENTS.md` §0), then hands off.

## Steps
1. Reproduce or restate the symptom precisely — screen, action, expected vs. actual.
2. Identify the module(s) via the route/screen name against `.agents/config.md`'s Module Registry.
3. Check `knowledge_brain\_SYSTEM\DIAGNOSTIC_PLAYBOOK.md` for a matching symptom pattern first — it may
   point straight at the cause.
4. Classify:
   - **Widget/UI bug** (layout, rendering, navigation, state not reflected in UI) → `/fix-widget-bug`.
   - **Logic/data bug** (wrong calculation, validation gap, API contract mismatch, security issue) →
     `/fix-logic-bug`.
   - Spans both → run both, logic fix first.
5. After the fix: `/test-and-verify`, then `/learn-and-improve`.

## Completion Report Template
```
Symptom: ...
Module(s): ...
Classification: Widget | Logic | Both
Root cause: ...
Fix summary: ...
Dispatched to: [workflow(s)]
```

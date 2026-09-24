---
description: Structured intake for a new feature/change request before implementation starts
version: 1.0.0
last_updated: 2026-08-19
---

# /get-requirement

## Purpose
Turn a vague ask ("add X to the app") into a concrete, brain-grounded implementation plan before writing
code.

## Steps
1. Restate the ask as a user-facing behavior change: what does the user see/do differently?
2. Identify affected module(s) via `.agents/config.md`'s registry; read those `MODULE_BRAIN.md`s.
3. Identify new/changed: screens, routes (check for a free route-name collision in `app_router.dart`),
   providers/state, API endpoints (new ones need backend coordination — flag this explicitly), security
   surface (any new sensitive field?).
4. Check `CROSS_MODULE_MAP.md` for every affected module — does this change ripple into another module's
   assumptions?
5. Produce a short plan: files to add/change, new route constant(s), new provider(s), open questions that
   need a product/backend answer before coding can start.

## Completion Report Template
```
Request: ...
Affected modules: [list]
New routes/screens: [list]
New/changed API endpoints: [list — flag any needing backend coordination]
Security surface changes: [list or none]
Open questions: [list or none]
Plan: [numbered steps]
```

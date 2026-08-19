---
description: Proactive sweep of one module against DANGER_ZONES.md and its own FORENSIC_TEMPLATE.md
version: 1.0.0
last_updated: 2026-08-19
---

# /module-bug-audit

## Purpose
Find latent bugs before a user reports them, using the accumulated `DANGER_ZONES.md` anti-pattern catalog
as a checklist against one module's actual code.

## Steps
1. Read `knowledge_brain\_SYSTEM\DANGER_ZONES.md` in full.
2. For each `DZ-00N` entry, grep the target module for the ❌ pattern.
3. For each hit, assess whether it's a real instance or a false positive (context matters — e.g. a
   `double` comparison might be fine outside a money/weight context).
4. For confirmed hits: file as a bug (don't auto-fix during an audit unless trivial and explicitly asked),
   noting file:line and which `DZ-00N` it matches.
5. Cross-check the module's own `FORENSIC_TEMPLATE.md` entries — any symptom listed there worth
   proactively verifying isn't currently happening (e.g. check a known race condition hasn't regressed).

## Completion Report Template
```
Module: ...
DANGER_ZONES checked: N
Confirmed hits: [file:line — DZ-00N — description]
False positives (context-cleared): N
Recommended next action: [file bugs | fix now (list) | none found]
```

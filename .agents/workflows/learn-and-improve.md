---
description: Write a fix's learnings back into the relevant brain docs so the brain doesn't go stale
version: 1.0.0
last_updated: 2026-08-19
---

# /learn-and-improve

## Purpose
Close the loop — a brain that isn't updated after the code changes underneath it actively misleads the next
session (`AGENTS.md` §9). Run this after every non-trivial fix.

## Steps
1. Update the touched module's `MODULE_BRAIN.md` — if the fix revealed an anti-pattern, add it to that
   doc's risks section (and flag it as a `DANGER_ZONES` candidate for the next `/build-system-brain` run).
2. Update `METHOD_INDEX.md` if a method's signature, location, or callers changed.
3. Update `BUSINESS_RULES.md` if a rule was clarified, corrected, or newly documented.
4. Update `CROSS_MODULE_MAP.md` if the fix touched a cross-module dependency that wasn't previously mapped.
5. If the bug pattern seems likely to recur elsewhere (same anti-pattern, different module), grep for it
   across other modules and flag matches — don't fix them speculatively, just flag for a follow-up
   `/module-bug-audit`.
6. Bump `last_updated` on every doc touched.

## Completion Report Template
```
Docs updated: [list, per module]
Anti-pattern flagged for DANGER_ZONES: Yes/No — [description]
Likely-recurring pattern found elsewhere: [list of modules to audit, or none]
```

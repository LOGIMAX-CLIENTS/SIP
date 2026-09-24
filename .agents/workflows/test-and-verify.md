---
description: Verify a fix actually works — static analysis, tests, manual-flow checklist
version: 1.0.0
last_updated: 2026-08-19
---

# /test-and-verify

## Purpose
Confirm a fix works end-to-end, not just that it compiles.

## Steps
1. `flutter analyze` on the changed files (and `dart format --set-exit-if-changed` if the repo enforces
   formatting) — fix any new warnings/errors before proceeding.
2. Run any existing widget/unit tests covering the touched module; if none exist for the fixed behavior and
   the bug is logic-layer (not a one-off UI tweak), consider adding a regression test.
3. Manual-flow checklist — walk the actual user flow the bug was in (or clearly state you could not run the
   app and are verifying via code-reading + static analysis only, per the house rule that UI changes need
   live verification when possible).
4. Re-check any security/financial-precision claims made in the fix's completion report against the actual
   running behavior if the app was run.

## Completion Report Template
```
flutter analyze: clean | N issues (list)
Tests run: [list] — pass/fail
Manual flow verified: Yes (describe steps) | No (reason)
Regression risk assessed: [modules/screens re-checked]
```

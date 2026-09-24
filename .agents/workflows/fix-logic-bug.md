---
description: Fix business-logic/data bugs — calculations, validation, API contract mismatches, security
version: 1.0.0
last_updated: 2026-08-19
---

# /fix-logic-bug

## Purpose
Fix bugs in the controller/service/model layer — wrong calculation, missed validation, API request/response
shape mismatch, or a security-relevant gap (unencrypted sensitive field, missing 409 handling, etc).

## Steps
1. Read the relevant `BUSINESS_RULES.md` for the module — confirm what the *intended* behavior is before
   changing code; if no rule is documented, that's itself a gap to fill in as part of this fix.
2. Trace the data flow (`DATA_FLOW.md` if it covers this path) from trigger to API call to state update.
3. Apply the minimal fix. If it touches §2 (financial precision) or §3 (security) of
   `AGENTS.md`/`SKILL.md`, re-read those sections and confirm compliance explicitly in the completion
   report.
4. If the fix reveals the documented `BUSINESS_RULES.md` entry was wrong, correct it now (not later) —
   see `AGENTS.md` §9.

## Completion Report Template
```
File(s) changed: ...
Business rule affected: RULE-{MODULE}-NNN (or "undocumented — added as part of this fix")
Root cause: ...
Fix: ...
Financial-precision reviewed: Yes/No/NA
Security reviewed: Yes/No/NA
```

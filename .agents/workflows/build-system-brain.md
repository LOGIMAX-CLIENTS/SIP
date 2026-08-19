---
description: Aggregate all module brains into the cross-cutting _SYSTEM/ documents
version: 1.0.0
last_updated: 2026-08-19
---

# /build-system-brain

## Purpose
Synthesize the per-module brains (`{BRAIN_DIR}\{Module}\*.md`) into system-wide documents that an agent
reads on *every* bug-diagnosis or cross-module task — these are the highest-leverage docs in the whole
system because they're read far more often than any single module brain.

## Prerequisites
Every module's `MODULE_BRAIN.md`, `CROSS_MODULE_MAP.md`, and `BUSINESS_RULES.md` should exist (brain status
🟡 or better) — run `/build-module-brain` first for any module still at ⬜.

## Steps

1. Read every module's `CROSS_MODULE_MAP.md` → build `_SYSTEM/MODULE_DEPENDENCIES.md` (who depends on
   `core/` and on whom; a Mermaid graph of feature-to-feature deps that shouldn't exist per the layering
   rule in `AGENTS.md` §1).
2. Read every module's `MODULE_BRAIN.md` "risks" sections + `FORENSIC_TEMPLATE.md` → build
   `_SYSTEM/DIAGNOSTIC_PLAYBOOK.md`: numbered "Rule N: symptom → check-first steps → ranked suspects"
   entries, deduplicated across modules.
3. Read every module's flagged anti-patterns → build `_SYSTEM/DANGER_ZONES.md`: numbered `DZ-00N` hard-stop
   rules, each with a ❌ wrong / ✅ correct snippet, and a "confirmed live in code" flag if the anti-pattern
   was actually found (not just theoretical).
4. Read `core/` module's `STATE_ANALYSIS.md` (providers/services shared across all features) → build
   `_SYSTEM/SHARED_SERVICES.md`.
5. Grep `lib/` for every distinct API endpoint string (method + path) across all modules → build
   `_SYSTEM/API_ENDPOINT_MAP.md` (one row per endpoint: method, path, which module(s) call it, encrypted
   fields, auth requirement if visible).
6. Scan for validation gaps (a form field with no matching `Validators`/`KycValidator` call) →
   `_SYSTEM/VALIDATION_GAPS.md`.
7. Grep for hardcoded values that look like they should be server config (rate-lock seconds, min/max
   amounts, GST %, denomination lists) → `_SYSTEM/HARDCODED_VALUES.md`.
8. Note any screen with a network call and no loading/error/retry state → `_SYSTEM/PERFORMANCE_RISKS.md`
   (extend with actual perf issues — large rebuild scopes, missing `const`, unbounded lists — if found).
9. Compute overall `_SYSTEM/SYSTEM_COVERAGE.md`: aggregate every module's `COVERAGE_TRACKER.md` into one
   table.
10. Update `{BRAIN_DIR}\_OVERVIEW\BUILD_SUMMARY.md` with a new round entry: what was rebuilt, coverage
    table snapshot, and any confirmed inaccuracies found in `STARTGOLD_DOCUMENTATION.md` or `AGENTS.md`
    itself (the module brains are the fact-check source of truth — see `AGENTS.md` §10).

## Completion Report Template

```
Round: N
Modules aggregated: N / 24 (23 features + core)
_SYSTEM docs written/updated: [list]
New DANGER_ZONES entries: N
New DIAGNOSTIC_PLAYBOOK entries: N
Overall coverage: N%
Inaccuracies found in hand-written docs: [list or none]
```

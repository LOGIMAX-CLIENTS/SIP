---
description: Snapshot of brain coverage, staleness, and known open risks across all modules
version: 1.0.0
last_updated: 2026-08-19
---

# /system-health

## Purpose
One-shot health check of the brain itself (not the app) — is it accurate and current enough to trust?

## Steps
1. Read `.agents/config.md`'s Module Registry — for each module, note brain status badge.
2. For each module with a brain, compare its `last_updated` (in each doc's frontmatter) against the actual
   `.dart` file modification times under `lib/features/{module}/` — flag modules where source postdates the
   brain (staleness).
3. Read `_SYSTEM/SYSTEM_COVERAGE.md` for the aggregate %.
4. Read `_OVERVIEW/BUILD_SUMMARY.md`'s open-inaccuracies list — confirm none have gone unresolved for more
   than a couple of rounds.
5. List modules still at ⬜ (never built) as the priority backlog.

## Completion Report Template
```
Overall coverage: N%
Modules stale (source newer than brain): [list or none]
Modules never built (⬜): [list or none]
Unresolved doc inaccuracies (>1 round old): [list or none]
```

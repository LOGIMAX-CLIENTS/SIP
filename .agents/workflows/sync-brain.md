---
description: Re-align an existing brain against drifted code, or port this whole .agents/knowledge_brain system to another Flutter project
version: 1.0.0
last_updated: 2026-08-19
---

# /sync-brain

## Purpose
Two related use cases:
1. **Drift repair** — the module's source has changed since its brain was built; patch the brain instead of
   a full rebuild when the change is small.
2. **Port to another project** — this exact `.agents/` + `knowledge_brain/` scaffold, structurally reused on
   a different (but similarly-shaped) Flutter app.

## Steps — Drift Repair
1. For the target module, diff current file list/method signatures against what `MODULE_BRAIN.md` and
   `METHOD_INDEX.md` claim.
2. Classify drift: **cosmetic** (renames, formatting) → patch in place; **structural** (new
   screens/providers, removed files, changed API contracts) → recommend `/build-module-brain` Force-Rebuild
   instead.
3. If patching: update only the affected sections, bump `last_updated`, log the round in
   `COVERAGE_TRACKER.md` with a "patched, not rebuilt" note.

## Steps — Port to Another Project
1. Copy `.agents/` and `knowledge_brain/{_OVERVIEW,_SYSTEM}` (skeleton, not per-module content) to the new
   project root.
2. Rewrite `.agents/config.md`: path variables, platform facts, and a fresh Module Registry scanned from
   the new project's actual folder structure (don't assume it matches this app's 23 modules).
3. Rewrite `CLAUDE.md` and `.agents/AGENTS.md` §0–§2 for the new project's actual architecture — do not
   copy security/financial rules verbatim if the new project isn't a fintech app; keep only what's
   generically true of the layering/state-management pattern if it also uses Flutter+Riverpod, otherwise
   rewrite that too.
4. Run `/build-module-brain` per module and `/build-system-brain` once for the new project.

## Completion Report Template
```
Mode: Drift Repair | Port
Modules checked/ported: N
Patched in place: [list]
Flagged for full rebuild: [list]
```

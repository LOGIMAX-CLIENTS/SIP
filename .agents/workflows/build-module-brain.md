---
description: Generate or refresh the 8-document knowledge_brain for one feature module by reading its actual Dart source
version: 1.0.0
last_updated: 2026-08-19
---

# /build-module-brain

## Purpose
Produce (or refresh) the standard 8-document brain for a single module under `{BRAIN_DIR}\{Module}\`, fully
code-grounded — every claim traceable to a file path (and line number where practical).

## Prerequisites
- Read `{AGENTS_DIR}\config.md` for the module's folder path and its entry in the Module Registry.
- If `{PROJECT_ROOT}\STARTGOLD_DOCUMENTATION.md` covers this module, read that section first as a head
  start — but verify every claim against live code rather than transcribing it. Note any drift you find.

## Modes
- **Build** (brain status ⬜): full generation from scratch.
- **Refresh** (brain status 🟡/🟢, source changed since `last_updated`): re-scan, update only what changed,
  bump `last_updated`, append a round entry to the module's `COVERAGE_TRACKER.md`.
- **Force-Rebuild**: discard existing docs, regenerate fully (use when the module was significantly
  restructured).

## Steps

1. **Inventory.** List every file under `lib/features/{module}/` (and any module-owned files elsewhere,
   e.g. route entries in `lib/routes/app_router.dart`). Note subfolder shape (`screens/`, `controller/` or
   `providers/`, `models/`, `services/`, `widgets/`).
2. **Read every screen file.** For each screen: route constant + path, purpose, Riverpod providers it
   watches/reads, API calls it triggers (directly or via a controller), navigation entry/exit points,
   security-relevant behavior (encryption, screenshot block, app-lock suppression), notable edge cases
   visible in the code (error states, empty states, loading states).
3. **Read every controller/notifier and service file.** Extract: public methods, the API endpoints they
   call (method + path), which request fields get encrypted, error mapping to `Failure` types, side effects
   (secure storage writes, provider invalidations, FCM registration, etc).
4. **Read every model file.** Extract: field names/types, `fromJson`/`toJson` shape, any validation baked
   into the model itself.
5. **Write the 8 documents** (template below). Keep `MODULE_BRAIN.md` under ~400 lines — push detail into
   the other 7 docs and link out.
6. **Cross-reference `core/`.** Note every `core/` service/provider this module depends on, for
   `CROSS_MODULE_MAP.md` and so `build-system-brain` can build the dependency graph later.
7. **Compute coverage.** Weighted: screens documented 25%, controller/service public methods documented
   25%, models documented 15%, API endpoints documented 15%, business rules captured 10%, cross-module deps
   captured 10%. Compare against actual counts (grep `class `, `Future<`, route entries). Record in
   `COVERAGE_TRACKER.md` with the round number, date, and % — 🔵 requires ≥95% **and** a manual spot-check
   that the docs match a fresh read of 2–3 files chosen at random.
8. **Report.** Print a completion summary (template below).

## Document Template

```
{BRAIN_DIR}\{Module}\
├── MODULE_BRAIN.md        — architecture, screen/route table, state deps, top risks (<400 lines)
├── METHOD_INDEX.md         — alphabetical class.method → file:line → callers
├── DATA_FLOW.md            — 2-5 end-to-end flows (e.g. screen load → API → state → render) with file:line
├── BUSINESS_RULES.md       — RULE-{MODULE}-NNN: plain-English rule + the code that implements it
├── CROSS_MODULE_MAP.md     — deps on core/, other features, shared widgets; Mermaid graph; known violations
├── STATE_ANALYSIS.md       — Riverpod providers/notifiers, model shapes, secure-storage keys touched
├── FORENSIC_TEMPLATE.md    — 4-6 "symptom → check first → likely suspects" entries for this module
└── COVERAGE_TRACKER.md     — round history, weighted %, badge
```

## Completion Report Template

```
Module: {Module}
Mode: Build | Refresh | Force-Rebuild
Files read: N
Docs written/updated: [list]
Coverage: N% (badge)
Drift found vs STARTGOLD_DOCUMENTATION.md: [none | list]
New cross-module deps discovered: [list or none]
Flagged for _SYSTEM synthesis: [DANGER_ZONES candidates, DIAGNOSTIC_PLAYBOOK candidates]
```

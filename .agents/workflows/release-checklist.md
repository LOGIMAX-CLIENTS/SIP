---
description: Pre-release checklist — version bump, native config review, security screens, store metadata
version: 1.0.0
last_updated: 2026-08-19
---

# /release-checklist

## Purpose
Catch release-blocking issues before a build is shipped to app stores.

## Steps
1. Confirm `pubspec.yaml` `version:` bumped appropriately (`AGENTS.md` §7).
2. Diff native config since last release: `android/app/src/main/AndroidManifest.xml`,
   `android/app/google-services.json`, `network_security_config.xml` (cert pinning), iOS equivalents —
   flag any change for explicit confirmation.
3. Re-run `/module-bug-audit` against `DANGER_ZONES.md` for any module touched since the last release.
4. Spot-check security screens (auth/OTP/MPIN/payment) still have screenshot block + app-lock behavior
   intact (`AGENTS.md` §3).
5. Confirm no debug/test payment-gateway credentials or logging left enabled
   (`core/security/secure_logger.dart` should not be logging sensitive fields).
6. Update `knowledge_brain\_OVERVIEW\BUILD_SUMMARY.md` with the release version and date.

## Completion Report Template
```
Version: old → new
Native config changes: [list or none]
DANGER_ZONES audit: clean | [findings]
Security screens spot-check: pass | [issues]
Debug/logging leftovers: none | [list]
```

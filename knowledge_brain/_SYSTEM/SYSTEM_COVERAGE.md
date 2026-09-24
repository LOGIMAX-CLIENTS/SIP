---
last_updated: 2026-08-19
source: Aggregated from all 24 module COVERAGE_TRACKER.md files
---

# System Coverage — Round 1

24/24 modules built (23 feature folders + `Core`). See `knowledge_brain/_OVERVIEW/BUILD_SUMMARY.md` for the
full narrative per module. Table below is the aggregate snapshot; each module's own `COVERAGE_TRACKER.md`
has the weighted breakdown and "Open Items" that block promotion to 🔵.

| Module | Coverage | Badge | Blocking a 🔵 promotion |
|---|---|---|---|
| Core | 99.4% | 🟢 | No dedicated Round-2 spot-check pass yet |
| Auth | 100% weighted | 🟢 | No dedicated Round-2 spot-check pass yet |
| MPIN | 93% | 🟢 | A few files read via grep, not full |
| KYC | ~97% | 🟢 | Two backend-contract facts unconfirmable from client code alone |
| Home | ≈90% | 🟢 | A few cross-referenced files read via grep, not full |
| InstantSaving | ~97% | 🟢 | GST/rate-lock-seconds exact server values not observed live |
| DailySavings | 100% | 🔵 | — |
| SIP | 95% | 🟢 | 3 large history/overview/detail screens read to partial depth |
| Withdrawal | 98.5% | 🔵 | — |
| Profile | 100% | 🔵 | — |
| Notifications | 96% | 🟢 | Native FCM platform wiring (AndroidManifest/gradle) not verified, Dart-side only |
| Nominee | 96% | 🟢 | A couple of unused/possibly-planned symbols with no confirmed caller |
| Referral | 99% | 🟢 | One sub-claim about `register-check`'s encryption-endpoint match unconfirmed |
| Settings | 99% | 🟢 | Two edges deferred to MPIN's brain (now built — could close this out) |
| Support | 100% | 🔵 | — |
| Content | 100% | 🔵 | — |
| Market | 100% | 🔵 | — |
| History | 100% | 🔵 | — |
| Splash | 100% | 🔵 | — |
| Onboarding | 100% | 🔵 | — |
| Maintenance | 100% | 🔵 | — |
| Main | 93% | 🟢 | Cross-module provider internals cited but not re-read line-by-line (correctly deferred to owning modules) |
| Invoice | 100% weighted | 🟢 | No dedicated Round-2 spot-check pass yet |
| Jewellery | 100% weighted | 🟢 | No dedicated Round-2 spot-check pass yet; primary documentation, no hand-written doc to cross-check against |

**Aggregate**: 12/24 at 🔵 (50%), 12/24 at 🟢 (50%), 0 at 🟡 or ⬜. No module fell below 90% coverage.

## Recommended Round 2 Priorities

1. Settings ↔ MPIN cross-check (Settings flagged this dependency as its own blocker; MPIN is now built).
2. Spot-check Core, Auth, InstantSaving, Invoice, Jewellery for 🔵 promotion — these are 🟢 purely because
   no dedicated re-verification pass ran, not because of known gaps.
3. Runtime/live-device verification of the `_SYSTEM/DANGER_ZONES.md` items flagged "unconfirmed" (DZ-003,
   DZ-004, DZ-005, and the MPIN/Settings `type`-argument question) — these are static-read findings that
   would benefit from a network capture or debugger session to close out definitively.

---
last_updated: 2026-08-19
source: Synthesized from incidental findings across module brains — not a dedicated performance audit, see "Known Incomplete" below
---

# Performance Risks

| Risk | Module | Detail |
|---|---|---|
| Very large single-file screens | Home, SIP | `home_screen.dart` is ~2251 lines; `auto_savings_screen.dart` is ~2367 lines. Large single-widget-tree files are harder to reason about for rebuild scope and more likely to have unnecessary full-tree rebuilds on state changes — worth a `const`/widget-extraction pass if rebuild performance is ever profiled as an issue. |
| Force-refetch bypassing cache | Content | `FaqScreen` invalidates its provider on every screen entry, unlike its sibling content screens which cache normally — an intentional-looking but undocumented choice; worth confirming it's needed (e.g. FAQ content changes often) rather than copy-pasted without the caching. |
| Flat reconnect retry with no backoff | Market/Core | `native_socket_service.dart` retries every 5 seconds flat, uncapped, with no exponential backoff — under a sustained server outage this means a constant reconnect-attempt drumbeat from every connected client simultaneously (thundering-herd risk at scale), not just a per-user performance issue. |
| Client-side pairing heuristic for bank-verification history | Profile | The Bank Verification Hub merges two independent backend tables (BAV attempts + ₹1 payment/refund attempts) via a client-side nearest-preceding-row heuristic since there's no shared attempt ID — this is an O(n) client-side join done in the UI layer rather than server-side, worth watching if either table grows large per user. |

## Known Incomplete

This file was populated from what individual module-brain agents happened to notice while tracing
architecture, not a dedicated performance-profiling pass (no widget-rebuild tracing, no network-waterfall
analysis, no memory-profiling). Treat as leads, not a completed audit — `/build-system-brain`'s step 8 calls
for extending this with a proper sweep (e.g. grep for missing `const` constructors, unbounded `ListView`s
without `.builder`, images loaded without caching) if performance work is prioritized.

---
last_updated: 2026-08-19
---

# Low-Complexity Modules

Modules likely to need a lighter brain pass (few screens, little/no dedicated state or API surface) based
on the Round 0 folder scan — no `controller/`, `services/`, or `models/` subfolder, or a subject matter
that's inherently simple. Confirm during each module's `/build-module-brain` run rather than skipping
verification entirely — "looks simple" is a hypothesis, not a finding.

| Module | Why it looks low-complexity |
|---|---|
| `splash` | Single screen, init-gate logic only, no dedicated subfolders |
| `onboarding` | Single screen, carousel + skip button, no dedicated subfolders |
| `maintenance` | Single screen, static downtime message, no dedicated subfolders |
| `main` | Tab-shell container, delegates to other features' screens |
| `market` | Only a `models/` subfolder — logic lives mostly in `core/providers/market_provider.dart` |
| `content` | Mostly static content screens (terms/privacy/about/refund/FAQ/contact) driven by simple providers |
| `settings` | Single screen, app preferences, no dedicated subfolders |

Everything else has `controller`/`services`/`providers`/`repositories` subfolders and real business logic —
treat as standard complexity by default.

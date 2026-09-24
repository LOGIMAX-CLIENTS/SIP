---
title: startGOLD Mobile — Master Agent Rules
version: 1.0.0
last_updated: 2026-08-19
---

# startGOLD Mobile (SIP) — Master Rules

This is the full rulebook for any AI agent (Claude Code, Antigravity/Gemini, or otherwise) working in this
repository. `{PROJECT_ROOT}\CLAUDE.md` is the short, always-loaded pointer to this file — if you're reading
this, you've already been told to read it in full before touching code. All `{TOKEN}` placeholders resolve
via `{AGENTS_DIR}\config.md` — read that file too; it has the path table and the module registry.

This system was ported from a sibling project (`fintect_application`, a Django fintech backend) that uses
the same `.agents/` + `knowledge_brain/` pattern. The pattern: **the brain is a hand/AI-curated Markdown
knowledge base, not a database or vector store** — you read it with your normal file tools, and you write
back to it after every fix so it stays accurate. There is no indexer, no embeddings, no retrieval pipeline.

---

## 0. Step Zero — Mandatory Before Touching Code

Before investigating or editing anything, in this order:

1. Read `{AGENTS_DIR}\config.md` (path variables, module registry, brain-status badges).
2. Identify which feature module(s) the task touches (see registry). Read that module's
   `{BRAIN_DIR}\{Module}\MODULE_BRAIN.md` in full.
3. For a **bug fix**: also read `{BRAIN_DIR}\_SYSTEM\DIAGNOSTIC_PLAYBOOK.md` (symptom → suspect lookup) and
   `{BRAIN_DIR}\_SYSTEM\DANGER_ZONES.md` (hard-stop anti-patterns), then
   `{AGENTS_DIR}\skills\flutter_fintech_mobile\SKILL.md`.
4. For a **cross-module task**: also read `{BRAIN_DIR}\{Module}\CROSS_MODULE_MAP.md` for every module
   involved, and `{BRAIN_DIR}\_SYSTEM\MODULE_DEPENDENCIES.md`.
5. If the module's brain status is ⬜ (not built) or badly stale (source files edited after the brain's
   `last_updated`), say so and offer to run `/build-module-brain` before proceeding — don't guess at
   architecture you haven't verified.
6. Only after 1–5: grep/read the actual `.dart` source, then write code.

If the user's request is trivial (typo fix, copy change, single-widget style tweak with no state/API/security
surface), Step Zero can be abbreviated to reading the relevant `MODULE_BRAIN.md` only.

---

## 1. Architecture & Coding Standards

- **Layering** (do not skip layers or reach downward past your own): `Screen (Widget)` → `Controller /
  StateNotifier (Riverpod)` → `Service (core/services or feature/services)` → `ApiClient (Dio, core/network)`.
  Screens must not call `ApiClient` directly; services must not build `Widget`s.
- **Feature-first structure**: each module under `lib/features/<name>/` owns its own `screens/`,
  `controller/` (or `providers/`), `models/`, `services/`, `widgets/`. Cross-feature reuse goes through
  `lib/shared/` (widgets/theme/utils) or `lib/core/` (network/security/global providers) — never import one
  feature's internals directly from another feature. Record any exception found in `CROSS_MODULE_MAP.md`.
- **State management**: Riverpod only. Prefer `StateNotifier`/`AsyncNotifier` for anything with async
  loading/error states over ad-hoc `setState` for non-trivial screens. Global cross-feature state
  (portfolio, market rates, user, connectivity, app-control) lives in `lib/core/providers/` — check there
  before adding a new provider that duplicates existing state.
- **Navigation**: all routes are registered centrally in `lib/routes/app_router.dart` as named routes with a
  static `String` constant on `AppRouter`. Never hardcode a route string literal at a call site — add a
  constant. `onGenerateRoute` has a fallback that redirects unknown routes to `/mpin` (if session valid) or
  `/login` — be aware new routes must be added to the `routes` map or they silently hit this fallback.
- **Naming**: `snake_case` files, `PascalCase` classes/widgets, `camelCase` methods/variables — standard Dart
  style, enforced by `analysis_options.yaml` + `flutter_lints`.

## 2. Financial-Calc Safety

- Money and metal-weight values are user-facing financial data. Do not introduce floating-point rounding
  bugs — check how the codebase currently represents amount/weight (`double` with explicit rounding vs. a
  dedicated decimal type) in `core/utils/validators.dart` and each module's `STATE_ANALYSIS.md` before
  adding new arithmetic. If you find raw `double` arithmetic feeding a payment amount with no rounding
  discipline, flag it — don't silently "fix" it without understanding the server-side contract.
  <!-- TODO(brain): confirm actual amount/weight representation once InstantSaving/SIP/Withdrawal
       STATE_ANALYSIS.md are built; update this rule with the real answer instead of a caveat. -->
- Rate values (buy/sell) are locked client-side for a configured duration after being fetched, to prevent
  a stale price being submitted after the market moves — see `core/providers/timer_provider.dart` and each
  purchase/withdrawal screen. Never bypass or extend a rate-lock timer to "make testing easier" in
  committed code.
- GST/tax and denomination values are server-driven config (`savings/config`, `savings/denominations/*`),
  not hardcoded constants — if you see a hardcoded tax rate or denomination list, treat it as tech debt to
  flag, not a pattern to copy.

## 3. Security — Non-Negotiable

- **Field-level encryption**: sensitive fields (password, otp, mpin, pan, aadhaar_number,
  bank_account_number, upi_id, amount-bearing financial fields) must go through
  `core/security/encryption_service.dart` (RSA-OAEP-SHA256) before hitting `ApiClient`. Never add a new
  sensitive field to a request payload without routing it through the existing encryption path — check how
  the interceptor (`core/security/api_interceptor.dart`) currently selects which fields to encrypt.
- **Secure storage only** for tokens, MPIN state, biometric flags — `flutter_secure_storage` via
  `core/security/secure_storage_service.dart`. Never `shared_preferences` for anything security-sensitive
  (that package is fine for pure UI prefs like language).
- **Session handling**: 401 → silent token refresh via interceptor; 409 → force logout + dialog (concurrent
  session / session invalidated). Don't swallow a 409 anywhere — it must propagate to
  `SessionManager`'s force-logout path.
- **App-lock**: MPIN or biometric re-auth on every resume from background (see
  `core/security/app_lifecycle_observer.dart`). Payment/UPI-intent screens set
  `AppLifecycleObserver.suppressAppLock = true` while a native payment SDK has focus — this is intentional,
  not a bug; don't "fix" it by removing the suppression without understanding why (it exists so leaving the
  app to authorize a UPI payment doesn't trigger a spurious app-lock).
- **Runtime protection**: root/jailbreak detection at startup (`root_detection_service.dart`), screenshot/
  recording block via `FLAG_SECURE` (`screenshot_security_service.dart`) — active on auth, OTP, MPIN, and
  payment screens at minimum. If you add a new screen that shows sensitive data (PAN, bank account, OTP),
  check whether it needs the same protection.
- **PCI DSS**: card/UPI details never touch app code — Cashfree/HyperSDK/Razorpay SDKs own that surface
  entirely. Never build a custom card-entry form.
- Full checklist lives in `{SKILLS_DIR}\flutter_fintech_mobile\SKILL.md` (OWASP MASVS L1/L2 mapping) — read
  it before any security-adjacent change.

## 4. Networking

- All HTTP goes through the single `ApiClient` (Dio) in `core/network/api_client.dart` with its interceptor
  chain — do not instantiate a raw `Dio()` or use `http` package directly in a feature.
- Live rates come over the Socket.IO connection in `core/network/native_socket_service.dart` — market-status
  and price frames are parsed from a pipe-delimited payload format; check the existing parser before
  assuming JSON.
- Handle offline/no-connectivity gracefully using `core/providers/connectivity_provider.dart` — every screen
  that hits the network should have a defined offline UX (banner, disabled CTA, retry), not a raw exception.

## 5. Error Handling

- Domain errors flow through `core/error/failures.dart` — map API/network errors to a `Failure` type at the
  service layer, don't let raw `DioException`s leak into widgets.
- User-facing error messages should be specific enough to act on (e.g. "Minimum purchase is ₹100") without
  leaking server internals (stack traces, raw exception text) to the UI.

## 6. Cross-Module Impact Analysis

Before changing anything in `lib/core/` (shared by every feature) or a widely-depended-on shared model
(e.g. user session state, portfolio state, market rate state), check
`{BRAIN_DIR}\_SYSTEM\MODULE_DEPENDENCIES.md` for every feature that consumes it, and re-verify each one
after the change — a core change with no visible compile error can still silently break a feature's runtime
assumption (e.g. a provider's data shape).

## 7. Release & Versioning

- `pubspec.yaml` `version:` is `major.minor.patch+buildNumber`. Bump `+buildNumber` on every release
  candidate; bump `patch`/`minor` per the actual scope of change.
- Native platform config (`android/app/src/main/AndroidManifest.xml`, `google-services.json`, iOS
  equivalents, `network_security_config.xml` for cert pinning) is release-sensitive — changes there need
  explicit confirmation before committing, same as CI/CD config in other projects.
- No branch-topology convention has been established yet in this repo (unlike `fintect_application`'s
  phase1/phase2 split) — if one gets adopted, document it here and in `config.md`.

## 8. Workflow Compliance

Prefer the relevant `/workflow` in `{WORKFLOW_DIR}\` over ad-hoc investigation once one exists for the task
type — see `{WORKFLOW_DIR}\00-INDEX.md`. Each workflow has a numbered Step list and a Completion Report
template; follow both so results stay comparable across sessions.

## 9. The Brain Is a Living Document — Write Back

After every non-trivial fix or feature addition, run (or manually apply the spirit of)
`/learn-and-improve`: update the touched module's `MODULE_BRAIN.md` (anti-patterns register),
`METHOD_INDEX.md`, and `BUSINESS_RULES.md` if a rule was clarified or corrected. A brain that isn't updated
after the code changes underneath it is worse than no brain — it actively misleads the next session. If you
notice a brain doc is stale (references a file/method that no longer exists, or a business rule you just
proved wrong), fix it immediately rather than leaving a note to fix it later.

## 10. Fact-Check Hand-Written Docs Against Live Code

`STARTGOLD_DOCUMENTATION.md` and `about startGOLD.md` at the project root are hand-written and can drift
from the code (see `_OVERVIEW/BUILD_SUMMARY.md` for any discrepancies the brain-build process has found).
When a module brain and the hand-written doc disagree, trust the module brain (it's code-grounded with
file:line references) — and flag the discrepancy in `_OVERVIEW/BUILD_SUMMARY.md` rather than silently
picking one.

## 11. Communication Style

Match the house style already established for this workspace: concise, file:line references for anything
code-specific, no invented specifics (rate-lock durations, thresholds, limits) without a citation to the
actual config/constant that defines them.

## 12. Environment Facts

See `{AGENTS_DIR}\config.md` §Platform Facts for the dependency/SDK table. Key one worth repeating: **three
payment SDKs are integrated** (Cashfree primary, HyperSDK, Razorpay) — check which one a given purchase/SIP/
withdrawal flow actually invokes before assuming it's Cashfree; don't assume a single gateway.

## 13. Route & Module Quick Reference

Full route table lives in `lib/routes/app_router.dart` (source of truth, ~65 named routes) and is mirrored
per-module in each `{BRAIN_DIR}\{Module}\MODULE_BRAIN.md`. Full module registry (23 feature folders + the
shared `core/` layer) is in `{AGENTS_DIR}\config.md`.

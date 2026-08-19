---
module: onboarding
brain_status: 🔵 100% (built, but module is an orphaned route — see verdict below)
last_updated: 2026-08-19
round: 1
---

# Onboarding — Module Brain

## 0. TL;DR Verdict (read this first)

`onboarding` is a **single-file carousel screen that is currently unreachable in the shipped
navigation graph.** `AppRouter.onboarding` (`/onboarding`) is registered
(`app_router.dart:65`, `:130`) but a repo-wide grep for every code path that could reach it
(`Navigator.push*Named`, `pushReplacementNamed`, `pushNamedAndRemoveUntil`) confirms **zero**
call sites anywhere in `lib/` navigate to it. `splash_screen.dart` — the only place a "first run"
decision would plausibly happen — never checks `SessionManager.hasSeenOnboarding()` (see
`Splash/MODULE_BRAIN.md`). The only other reference to `AppRouter.onboarding` is a defensive
entry in `core/security/app_lifecycle_observer.dart:150`'s route-skip list (so the app-lock
lifecycle observer won't stack an MPIN prompt on top of onboarding *if* it were ever shown) — that
is not a navigation trigger.

This is the same class of finding as `daily_savings` (see that module's brain): a fully-built,
styled screen with real (if partial) backend integration, wired into the router, but with no
in-app entry point. Unlike `daily_savings`, this one is not a dead-end stub — the code itself is
functionally complete for what it does — it's simply never invoked.

**Also drift vs both `STARTGOLD_DOCUMENTATION.md` §3.2 ("skip button") and the task framing
("Carousel + skip button")**: there is **no skip button** anywhere in
`onboarding_screen.dart` — confirmed via full read plus a case-insensitive grep for "skip" (zero
matches). The only interactive element is one CTA button that either advances one page at a time
or completes the flow on the last page.

## 1. Inventory

| Path | Role |
|---|---|
| `lib/features/onboarding/onboarding_screen.dart` | Sole file (256 lines). `ConsumerStatefulWidget` `OnboardingScreen` + plain classes `OnboardingModel` (data holder) and `OnboardingPage` (`StatelessWidget` for one slide). |

No `screens/`, `controller/`, `providers/`, `models/`, `services/`, or `widgets/` subfolders exist
under `lib/features/onboarding/`.

Route registration (external, per convention):
- `lib/routes/app_router.dart:5` — `import '../features/onboarding/onboarding_screen.dart';`
- `lib/routes/app_router.dart:65` — `static const String onboarding = '/onboarding';`
- `lib/routes/app_router.dart:130` — `onboarding: (context) => const OnboardingScreen(),`

## 2. Screen: OnboardingScreen

`onboarding_screen.dart:12-159`. `ConsumerStatefulWidget`, `_OnboardingScreenState`.

| Attribute | Detail |
|---|---|
| Route | `/onboarding` (`AppRouter.onboarding`) — **unreachable, see §0** |
| State mgmt | Riverpod (`ConsumerStatefulWidget`) for content loading; local `setState` for `_currentPage` (`:21`, `:52`) |
| Providers watched | `onboardingContentProvider` (`core/services/content_service.dart:147-151`) |
| API calls | `POST users/content/onboarding` (via `ContentService.getOnboardingContent()`, `content_service.dart:8-20`) — indirect, through the provider |
| Encryption | None — public, unauthenticated content endpoint |
| Navigation out | `Navigator.pushReplacementNamed(context, AppRouter.login)` — only on completing the last slide (`:91-95`) |
| Security | None screen-specific |

### 2.1 Content loading (`onboardingContentProvider`, `:25`)

`AsyncValue.when` over three states:
- **`data`** (`:30-109`): if the API returned a non-empty `slides` list, maps each entry to
  `OnboardingModel(title, description, image)` (`:31-38`, reading keys `title`/`desc`/`image` —
  note the API key is `desc`, not `description`). If the list is empty, falls back to **a single
  hardcoded slide** — "Artisanal Security" with description text and a remote placeholder image
  URL `https://cdn.gold.com/slides/1.png` (`:39-46`). This fallback is one slide, not a
  multi-slide deck.
- **`loading`** (`:110-112`): `CircularProgressIndicator`.
- **`error`** (`:113-129`): error icon + "Failed to load content" + a `TextButton` that calls
  `ref.refresh(onboardingContentProvider)`. **This branch is effectively unreachable in
  practice** — `ContentService.getOnboardingContent()` catches its own exceptions and returns `[]`
  rather than rethrowing (`content_service.dart:17-19`), so the `FutureProvider` never actually
  completes in an error state from a network failure; it always resolves to `data` (empty →
  fallback slide, or populated).

### 2.2 Carousel mechanics

`PageView.builder` + `_pageController`, page-change tracked via `setState(() =>
_currentPage = index)` (`:50-57`). A dot-indicator row (`buildDot`, `:134-158`) renders one
`AnimatedContainer` per slide, widened/colored for the active index. Each slide is rendered by
`OnboardingPage` (`:170-254`): full-bleed `Image.network` background (icon fallback on load
error), a dark gradient scrim, and a bottom-anchored title/description card with staggered
`FadeInAnimation` (`shared/widgets/animations.dart`).

### 2.3 CTA button (`CustomButton`, `shared/widgets/custom_button.dart`)

Label switches based on position: `"Advance Forward"` on any non-last page,
`"Begin Your Legacy"` on the last page (`:75-77`). Behavior on tap (`:87-102`):
- **Not last page** → `_pageController.nextPage(duration: 600ms, curve: fastOutSlowIn)`.
- **Last page** → `await SessionManager.setOnboardingSeen()` (writes the
  `hasSeenOnboarding` secure-storage flag to `true`, `session_manager.dart:50-52` →
  `secure_storage_service.dart:51-53`), then
  `Navigator.pushReplacementNamed(context, AppRouter.login)` — **always** goes to `/login`,
  never checks or preserves any prior mpin/session state.

**No skip button exists.** The only way off this screen (were it ever reachable) is paging
through every slide.

## 3. Top Risks

1. **Orphaned route.** If any future deep link, push-notification payload, marketing link, or a
   restored "first-run" check in `splash_screen.dart` targets `/onboarding`, it will now work
   end-to-end (the screen itself is functional) — but as shipped today nothing reaches it.
2. **Write-only flag.** `SessionManager.setOnboardingSeen()` sets `hasSeenOnboarding=true` in
   secure storage, but nothing in the codebase reads `SessionManager.hasSeenOnboarding()` except
   its own definition — a repo-wide grep shows the getter is never called. The flag currently has
   zero effect on app behavior. **Unconfirmed** whether this is vestigial (a since-removed
   conditional-onboarding branch in splash) or forward-looking (prepared for a future gate that
   hasn't been wired yet).
3. **Doc/task mismatch on "skip button."** Both `STARTGOLD_DOCUMENTATION.md` §3.2 and the general
   expectation of an onboarding carousel assume a skip control. None exists in code — flagged in
   `_OVERVIEW/BUILD_SUMMARY.md`.
4. **Silent API-failure swallowing.** `ContentService.getOnboardingContent()`'s `catch (e) {
   return []; }` means a real backend error (500, timeout, malformed JSON) is indistinguishable
   from "the server legitimately returned zero slides" — both silently show the same one hardcoded
   fallback slide. No error is surfaced to logs/analytics from this path.

## 4. See Also
- `METHOD_INDEX.md` — every method, file:line, callers.
- `DATA_FLOW.md` — content-load flow and the completion flow.
- `BUSINESS_RULES.md` — RULE-ONBOARDING-001..005.
- `CROSS_MODULE_MAP.md` — deps on `core/`, `shared/`; Mermaid graph.
- `STATE_ANALYSIS.md` — provider + local state, secure-storage key.
- `FORENSIC_TEMPLATE.md` — symptom → suspect entries.
- `COVERAGE_TRACKER.md` — Round 1 coverage.

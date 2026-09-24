---
module: onboarding
last_updated: 2026-08-19
---

# Onboarding — Forensic Template

| Symptom | Check first | Likely suspects |
|---|---|---|
| "Onboarding never shows for new users" | This is expected/by-design today, not a bug in this screen — confirm nobody has recently added a `hasSeenOnboarding()` check to `splash_screen.dart` that broke; as of Round 1 no such check exists anywhere. | Missing wiring in `splash_screen.dart._initializeApp()` — the screen itself works, it's just never invoked. |
| Onboarding shows only 1 slide instead of the expected deck | Check `POST users/content/onboarding` response shape — the screen expects `data.slides` as a non-empty list of `{title, desc, image}`. An empty/missing list silently falls back to the single hardcoded "Artisanal Security" slide. | Backend content not configured for this endpoint; wrong response shape (e.g. key `description` instead of `desc` — code specifically reads `desc`, `onboarding_screen.dart:35`). |
| "Retry" button on the error state does nothing useful | `ContentService.getOnboardingContent()` never actually surfaces an `AsyncError` — it catches internally and returns `[]`. The error branch UI is dead code in practice; retrying will just show the fallback slide again if the underlying issue (e.g. backend down) persists. | Backend `users/content/onboarding` genuinely erroring — check server logs, not this screen. |
| User completes onboarding but is asked to onboard again next launch | Confirm `SessionManager.setOnboardingSeen()` actually persisted (`flutter_secure_storage` write succeeded) — but also remember nothing currently reads this flag, so "asked again" would only happen if/when a future gate is added and doesn't handle a write failure gracefully. | Secure storage write failure (rare); or — if a future gate is added — a logic bug in whatever code path is meant to call `hasSeenOnboarding()`. |
| Images on onboarding slides show a broken-image icon | `Image.network(data.image, ...)` has an `errorBuilder` fallback (`onboarding_screen.dart:183-187`) that shows a gray placeholder icon — this is expected behavior for a bad/unreachable URL, not a crash. | Backend-provided `image` URL unreachable, malformed, or (for the hardcoded fallback) the placeholder domain `cdn.gold.com` not resolving. |

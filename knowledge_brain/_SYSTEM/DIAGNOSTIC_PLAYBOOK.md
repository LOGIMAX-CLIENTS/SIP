---
last_updated: 2026-08-19
source: Synthesized from all 24 Round-1 module brains' FORENSIC_TEMPLATE.md files
---

# Diagnostic Playbook

Symptom → check-first steps → ranked likely suspects. Check here before re-deriving architecture from
scratch (`AGENTS.md` §0 Step Zero for bug fixes).

## Rule 1: User reports being logged out randomly / session drops unexpectedly
1. Check for a `409` response anywhere in recent logs — `SessionManager`'s force-logout path fires on any
   409, by design (`AGENTS.md` §3). This may be correct behavior (concurrent session) or a false positive.
2. Check `core/security/api_interceptor.dart`'s 401-refresh logic — a refresh failure also routes to logout.
3. If it happens specifically on app resume, check `core/security/app_lifecycle_observer.dart`'s app-lock
   trigger — this is a re-auth prompt, not a true logout, but can look identical to a user.

## Rule 2: A "sensitive" field appears to have reached the server in plaintext
1. Check `AppConfig.sensitiveFields` (`core/config/app_config.dart`) for the exact field name — coverage
   is per-field, not per-endpoint (see `_SYSTEM/DANGER_ZONES.md` DZ-004).
2. Check `AppConfig.encryptedEndpoints` for a matching path — the interceptor uses substring matching, so a
   new sub-path (e.g. `sip/custom/create` vs. `sip/create`) can silently miss (DZ-003).
3. Check the request-building code isn't constructing the path with an accidental Dart escape sequence
   (`\v`, `\n`, etc. in a non-raw string) — confirmed real in `withdrawal_service.dart` (DZ-005).
4. Check whether the RSA key was ready at request time — encryption fails open if not (DZ-002).

## Rule 3: A response field that should be decrypted looks unchanged/garbled
`EncryptionService.decrypt()` is currently a no-op (DZ-001) — this is not a bug in your code, it's a known
gap in `core/`. Confirm with the Core module brain before spending time debugging elsewhere.

## Rule 4: Live gold/silver rates are stuck, frozen, or show zero
1. Check `core/network/native_socket_service.dart`'s connection state — it's a raw `web_socket_channel`
   (not Socket.IO despite older docs), with a flat 5-second reconnect, no backoff.
2. Check the market-status frame (`5|<commodity_id>|<commodity_name>|<status>`) — status is tracked
   per-commodity, not globally; a "gold frozen, silver fine" report is consistent with this.
3. Check `home_screen.dart:97-125`'s rate-lock race-condition guard — if the first rate frame after
   reconnect is `0`, it deliberately re-locks on the next non-zero frame rather than displaying `0`; this
   is intentional, not a bug, but can look like a freeze during the gap.
4. Check `core/providers/timer_provider.dart` for a stuck countdown if the UI shows a rate but a stale
   timer.

## Rule 5: A purchase/SIP/withdrawal shows "success" but the rate/amount looks wrong
1. Check for a KYC-detour mid-flow — InstantSaving's rate can silently re-lock during a KYC interruption
   with no re-confirmation shown to the user (`payment_handler.dart:144-151`).
2. Check for the weight-precision mismatch: UI displays a 6-decimal floor-truncated value; the actual
   payload independently recomputes at 4-decimal rounding — these can legitimately differ by a small
   amount without either being "wrong" per se.
3. Check `savings/config`'s live `gst` value against the `3.0` client-side fallback — if the server value
   changed and the fallback didn't, purchases made during a network hiccup could compute GST inconsistently.

## Rule 6: A form submission is silently mis-categorized or an argument seems ignored
1. Check for a default value that isn't a key in the mapping the UI/submit logic uses — confirmed pattern
   in `EnquiryFormScreen`'s ticket-type chips (DZ-011). Grep for the literal default string against the
   map/enum it's supposed to match.
2. Check whether a navigation argument is actually read by the destination screen, or silently dropped —
   confirmed in the Support module (`initial_type: 'Custom SIP'` dropped) and suspected in MPIN (Settings'
   `/mpin` navigation with no `type` argument).

## Rule 7: A screen/feature seems unreachable even though it "should" work
Check `_SYSTEM/DEAD_CODE_AND_ORPHANED_ROUTES.md` first — this has happened often enough (5+ confirmed
instances: daily-savings, onboarding, support, about, settings) that "orphaned route, not a bug" is a
higher-prior hypothesis than it would be in a codebase without this history.

## Rule 8: A bank-account/UPI-related flow behaves unexpectedly during withdrawal
1. Confirm which screen the flow is actually using — the withdrawal flow uses SIP's
   `BankAccountPickerScreen`, NOT the `UpiSelectionScreen` that physically lives in `withdrawal/screens/`
   (that screen is only reachable from Instant Saving and has a confirmed navigation quirk — see DZ-011).
2. If it's a new-bank-account flow, check for the Dart string-escape path bug (DZ-005) before assuming a
   backend issue — the request may not even be reaching the intended endpoint.
3. UPI payout itself is implemented but currently disabled in the UI (bank-account-only) — "why can't I add
   UPI" may be a UI-flag question, not a bug.

## Rule 9: Language/locale setting doesn't seem to do anything or doesn't persist
Known, documented gap, not likely a regression: `LanguageState.translations` is permanently empty (the
fetch method's body is commented out with "English by default for now"), so only built-in Flutter widget
locale strings change — the app's own UI copy is never translated. Separately, the selected language does
not survive an app restart (`LanguageNotifier._init()` hardcodes `'en'`; the `LanguageCache` class built to
prevent this has zero callers). See `Settings/BUSINESS_RULES.md` RULE-SETTINGS-004/005.

## Rule 10: An enquiry/ticket ends up under the wrong category
See Rule 6 — this is the `kTicketTypes` default-value mismatch (DZ-011), a confirmed reproducible bug, not
speculative.

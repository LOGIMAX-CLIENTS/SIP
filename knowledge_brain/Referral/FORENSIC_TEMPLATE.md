# Forensic Template — Referral

"Symptom → check first → likely suspects" entries for triaging bug reports in this module.

---

### Symptom: Referral code not applied at signup (referee reports they entered a code but referrer's
### count never increased)

**Check first**:
1. Confirm the code was actually non-empty when submitted — `_referralController.text.trim()` at
   `registration_screen.dart:538,553` trims whitespace but does not validate format/existence; a typo'd
   code is sent as-is to the server with no client-side existence check.
2. Confirm which of the two calls (`register-check` vs `register`) actually persists the referral link
   server-side — this codebase sends `referral_code` to **both** endpoints
   (`auth_service.dart:128-147,180-197`) but only the backend knows which call is authoritative. If the
   backend only honors the code on `register-check` (validation-only step) and silently ignores it on
   the final `register` call (or vice versa), the client would show no error either way.
3. Check whether the referee actually completed **PIN setup**, not just registration — `_handleSetPin()`
   in `pin_creation_screen.dart:392+` calls `register()` (which carries the code) only as "Step 1"; if
   the user abandoned the flow after registration but before setting a PIN, it's unconfirmed whether the
   backend already recorded the referral link at that point.

**Likely suspects**:
- Backend referral-code validation/matching logic (not visible in this Flutter codebase — this is a
  server-side investigation, this brain can only confirm the client sent the right value).
- Self-referral or already-referred guard rejecting silently (pattern seen in the sibling backend's
  Referrals module, `fintect_application` — **unconfirmed** whether startGOLD's backend has the same
  guard, but worth asking).
- Case-sensitivity or whitespace mismatch between what the referrer's code actually is
  (`ReferralData.referralCode`, uppercase-styled in the UI via `letterSpacing`/font, but the underlying
  string case is whatever the server returned) and what the referee typed — client does not
  uppercase/normalize `_referralController.text` before sending.

---

### Symptom: Referee status stuck on "Pending" / reward stuck on "Hold" indefinitely

**Check first**:
1. Confirm this is actually a stale-data issue, not a genuine pending state — reload
   `RefereeListScreen`; both screens force-invalidate on every mount (`referee_list_screen.dart:23-24`),
   so a simple navigate-away-and-back should reflect the latest server state. If it doesn't change, the
   state truly is stuck server-side.
2. Check the exact string value of `rewardStatus` returned by the API for that referee — the client only
   distinguishes 4 known values (`disbursed`, `hold`, `pending`, `no reward`); anything else renders with
   the generic grey/info style, which could visually look like "nothing is happening" even if the server
   has a 5th intermediate status the UI doesn't have a bespoke chip for.

**Likely suspects**:
- Backend reward-condition/threshold logic (referee's qualifying purchase amount, market-open gating,
  etc.) — not visible client-side, same caveat as above.
- If the app's own referee-list UI never refreshes stale cached data in a long-lived session (user keeps
  the app backgrounded/foregrounded without a full navigation remount) — check whether
  `refereeListProvider` is being invalidated on app resume anywhere outside this module (grep did not
  find any `AppLifecycleObserver`-driven invalidation for this provider — unconfirmed whether one should
  exist).

---

### Symptom: "Refer & Earn" screen shows a blank/empty code card, or code is literally the empty string

**Check first**:
1. Distinguish a genuine empty response from a swallowed network error — per
   `BUSINESS_RULES.md` RULE-REFERRAL-006, both are visually identical (empty code, no reward text, hero
   header falls back to the hardcoded "Invite a friend..." template). Add a temporary debug log or check
   `kDebugMode` console output — `ReferralService.fetchReferralData()` already logs status code + body in
   debug builds (`referral_service.dart:76-79`).
2. Confirm the auth token / session is valid — the request body is empty (`data: {}`), so the server must
   be identifying the user purely from the auth header; a silently-expired/invalid token would likely
   produce a 401 (handled by `Core`'s interceptor, not this module) rather than a referral-specific error.

**Likely suspects**:
- Token refresh race on cold app start — if `ReferralScreen` is somehow reached before the session/token
  interceptor has fully initialized (unlikely given normal navigation, but possible via a deep link),
  the request could 401/fail silently into `ReferralData.empty`.
- Server not yet having generated a referral code for a very-newly-registered user (timing/eventual
  consistency) — backend concern, not verifiable from this codebase.

---

### Symptom: "Share" button opens the native share sheet with a wrong or missing reward amount

**Check first**:
1. Look at `_shareReferral(code, rewardAmount)`'s call site — it's passed `data.rewardAmount` directly
   from the currently-loaded `ReferralData` (`referral_screen.dart:454`, closure captures `code`/
   `rewardAmount` from `_buildPremiumCodeCard`'s parameters, ultimately from `_buildBody`'s `data`).
   If the screen is mid-loading or the fetch failed, `rewardAmount` is `''` at the point the button
   renders — but the button is only rendered inside `_buildBody`, which does run even for `.empty` data
   (see Flow 1), so an empty reward amount in the shared text (`'🌟 Join me... earn ₹ in free Digital
   Gold!'` — note the blank after ₹) is a realistic bug, not hypothetical.
2. Confirm which `ReferralData` was actually in scope when the button was tapped — no memoization issue
   expected (single build pass), but worth checking if this was reported right after a slow network load.

**Likely suspects**:
- Fetch still in-flight or failed silently (see RULE-REFERRAL-006) at the moment the user tapped Share
  before the loading spinner had a chance to appear/complete — race between initial paint and provider
  resolution.

---

### Symptom: Copy Code button appears to do nothing (code not actually on clipboard when pasted
### elsewhere)

**Check first**:
1. Check timing — the clipboard is deliberately auto-cleared 60 seconds after copy
  (`referral_screen.dart:407-410`). If the user pastes more than a minute after copying, the clipboard
  will contain an empty string by design, not a bug.
2. Confirm the `code` variable passed to the copy handler wasn't empty at tap time (same empty-string
   risk as the Share flow above, if data hadn't loaded yet).

**Likely suspects**:
- User error / expected 60s TTL behavior (most likely).
- Same "data not loaded yet" race as the Share symptom above.

---

### Symptom: Tapping "Friends Referred" stats banner does nothing

**Check first**:
1. Confirm `data.totalReferrals > 0` — the `GestureDetector`'s `onTap` is explicitly `null` when
   `totalReferrals == 0` (`referral_screen.dart:246`), by design (RULE-REFERRAL-005). This is expected
   behavior, not a bug, if the user genuinely has zero referrals.
2. If `totalReferrals` is visibly > 0 on screen but the tap still does nothing, check for a navigation
   stack issue (e.g. already on `/referee-list` in some embedded-tab context) rather than the referral
   module's own logic, which is a single `Navigator.pushNamed` call with no guard beyond the count check.

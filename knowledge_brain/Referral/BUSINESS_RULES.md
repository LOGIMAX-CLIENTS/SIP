# Business Rules — Referral

Plain-English rule + the code that implements (or fails to implement) it. Numbered RULE-REFERRAL-NNN.

---

### RULE-REFERRAL-001 — Referral code entry is optional at signup
The referral-code field on the registration screen has no required-field validation and is labeled
"Referral Code (Optional)".
- **Code**: `lib/features/auth/registration/registration_screen.dart:305-306` (label text), no
  validator wired to `_referralController` — confirmed by absence of a validator call in the submit
  handler for that specific field (other fields like name/email/dob do have inline validation, referral
  code does not).

### RULE-REFERRAL-002 — Referral code, if entered, is sent to the server twice during signup
Once at the pre-registration validation step (`register-check`), and again at the final registration
step (`register`) — both times as the raw trimmed text, both times under the JSON key `referral_code`.
- **Code**: `lib/core/services/auth_service.dart:180-197` (`register-check`, field at line 193) and
  `lib/core/services/auth_service.dart:128-147` (`register`, field at line 143).
- Client-side there is no caching/reuse of a "code was already validated" flag between the two calls —
  each call re-sends the code independently.

### RULE-REFERRAL-003 — The registration payload (including the referral code) is transport-encrypted
`POST users/auth/register` matches the substring `'auth/register'` in `AppConfig.encryptedEndpoints`
(`lib/core/config/app_config.dart:52`), so `ApiClient`'s interceptor RSA-OAEP-SHA256-encrypts the entire
JSON body — the referral code travels encrypted alongside the other registration fields, not because it
is itself flagged sensitive, but because the whole endpoint is.
- **Code**: `lib/core/security/api_interceptor.dart:134-179` (endpoint-level encryption check), the
  `encryptedEndpoints` list (`app_config.dart:47-71`).
- Note: `POST users/auth/register-check` does **not** appear to match any `encryptedEndpoints` entry
  (`'register-check'` is not itself a listed substring and doesn't contain `'auth/register'` — wait,
  it does contain `'auth/register'` as a substring of `'auth/register-check'`... **unconfirmed**, depends
  on exact `path.contains(e)` matching semantics against the actual request path string; flagged for
  verification rather than asserted either way).

### RULE-REFERRAL-004 — This module performs zero client-side reward calculation
Both `total_earned` and `reward_amount` are opaque strings/numbers returned directly by the server and
displayed as-is; the client never computes a reward amount from a referee count or a rate table.
- **Code**: `ReferralData.fromJson` (`referral_service.dart:28-53`) — every reward-related field is a
  passthrough (`json['reward_amount']?.toString()`, `double.tryParse(json['total_earned']...)`), no
  arithmetic performed on them anywhere in the module.

### RULE-REFERRAL-005 — Stats banner (and the link to the referee list) only shows once the user has
### referral activity
The "Friends Referred" stats card, and therefore the only client-side entry point into
`RefereeListScreen`, is hidden entirely when both `totalReferrals == 0` and `totalEarned == 0`.
- **Code**: `referral_screen.dart:244-252` — `if (data.totalReferrals > 0 || data.totalEarned > 0)`.
- Consequence: a user with zero referrals has no way to reach `/referee-list` from the UI at all (the
  route is still reachable by direct `Navigator.pushNamed` from elsewhere in principle, but nothing else
  in the app currently links to it — see `CROSS_MODULE_MAP.md`).

### RULE-REFERRAL-006 — API failures are indistinguishable from "zero referrals" to the end user
Both `ReferralService.fetchReferralData()` and `RefereeListService.fetchList()` catch every exception
internally and return an empty-shaped model rather than propagating a `Failure`/error state.
- **Code**: `referral_service.dart:94-97` (catch block returns `ReferralData.empty`),
  `referee_list_service.dart:75-78` (catch block returns `RefereeListData.empty`).
- This is a deviation from `AGENTS.md` §5 ("map API/network errors to a `Failure` type at the service
  layer"). Practical impact: a network outage renders identically to a legitimate empty state — no
  retry affordance is shown to the user on `ReferralScreen` (contrast with `RefereeListScreen`, which
  does render a Retry button, but only on the *build-time* error branch, which this catch pattern never
  triggers — see `FORENSIC_TEMPLATE.md`).

### RULE-REFERRAL-007 — Both referral screens force a fresh network fetch on every visit
Neither screen relies on Riverpod's default provider caching; both explicitly `ref.invalidate(...)` in
`initState` via a `Future.microtask`.
- **Code**: `referral_screen.dart:26-32`, `referee_list_screen.dart:20-25`.
- Trade-off: guarantees fresh data (reward status can change server-side after a referee's first
  purchase) at the cost of a network round-trip + loading spinner on every navigation to these screens,
  even back-to-back within the same session.

### RULE-REFERRAL-008 — Reward status per referee is a small closed set of known strings, rendered via
### a fixed style map, with an unstyled fallback for anything else
`_RefereeCard._style()` recognizes exactly `disbursed`, `hold`, `pending`, `no reward` (case-insensitive)
and falls back to a generic grey/info style for any other value.
- **Code**: `referee_list_screen.dart:195-228`.
- The same 4-value map is reused for both the join-status chip (`item.status`) and the reward-status
  chip (`item.rewardStatus`) — these are conceptually different fields (one tracks "did they sign up",
  the other "did the reward get paid") sharing one status vocabulary; if the server ever uses a status
  string in one field that only makes sense for the other, it will render with whatever style happens to
  match, not necessarily meaningfully.

### RULE-REFERRAL-009 — The reward metal type (gold vs. everything else) is styled specially
`_RefereeCard` gives a gold-gradient badge only when `item.reward.toLowerCase() == 'gold'`; every other
non-empty reward value (e.g. presumably "Silver") gets a flat grey badge.
- **Code**: `referee_list_screen.dart:233,337-348`.
- Unconfirmed whether "Silver" rewards are actually issued by the referral programme (startGOLD supports
  both metals per `config.md` platform facts) — if they are, this UI treats them as visually
  second-class (grey, same as an unrecognized value) rather than giving Silver its own accent color.

# State Analysis — Referral

## Riverpod Providers

| Provider | Kind | State type | File:line | Invalidated by |
|---|---|---|---|---|
| `referralServiceProvider` | `Provider` | `ReferralService` | `referral_service.dart:102-103` | Never explicitly — pure DI, no state to invalidate |
| `referralDataProvider` | `FutureProvider` | `ReferralData` | `referral_service.dart:105-107` | `ReferralScreen.initState()` on every mount (`referral_screen.dart:29-31`) |
| `refereeListServiceProvider` | `Provider` | `RefereeListService` | `referee_list_service.dart:84-85` | Never explicitly |
| `refereeListProvider` | `FutureProvider` | `RefereeListData` | `referee_list_service.dart:87-89` | `RefereeListScreen.initState()` on every mount (`referee_list_screen.dart:23-24`); also manual retry button on the (practically dead) error branch (`referee_list_screen.dart:84`) |

No `StateNotifier`/`AsyncNotifier` in this module — both screens are driven by plain `FutureProvider`s
with no mutation methods (the providers are read-only views of server data; there is no local
"claim reward" or "resend invite" action that would need a notifier).

No global/cross-feature provider is declared or consumed here beyond `selectedTabProvider` (owned by
`features/main/main_screen.dart`, read-only usage at `referral_screen.dart:118`).

## Model Shapes

### `ReferralData` (`referral_service.dart:6-64`)

| Field | Type | Source JSON key | Notes |
|---|---|---|---|
| `referralCode` | `String` | `referral_code` | Defaults `''` |
| `totalReferrals` | `int` | `total_referrals` | `int.tryParse(...toString())`, defaults `0` — tolerant of the server sending either a number or a numeric string |
| `totalEarned` | `double` | `total_earned` | Same tolerant-parse pattern, defaults `0` |
| `rewardAmount` | `String` | `reward_amount` | Kept as raw string — UI does its own `₹` prefix logic (see `BUSINESS_RULES.md` RULE-REFERRAL-004 area) |
| `shareLink` | `String` | `share_link` | **Parsed but never read anywhere in the screen** — `_shareReferral` builds its own hardcoded share text/link instead of using this field. Dead field client-side. |
| `title` | `String` | `title` | Server-driven hero headline; falls back to a hardcoded rich-text template if empty |
| `bulletPoints` | `List<String>` | `bullet_points` | Accepts either `[{content: "..."}]` objects or plain strings in the source array |

`ReferralData.empty` (`referral_service.dart:55-63`) is the canonical zero-value, used both for
legitimate "no data yet" and for every error path (see `BUSINESS_RULES.md` RULE-REFERRAL-006).

### `RefereeItem` (`referee_list_service.dart:7-35`)

| Field | Type | Source JSON key | Notes |
|---|---|---|---|
| `referee` | `String` | `referee` | Display name; first-letter used for avatar |
| `referralDate` | `String` | `referral_date` | Expected `YYYY-MM-DD`, manually re-parsed for display |
| `reward` | `String` | `reward` | Defaults `'—'` (em dash) — used as the "has a reward" sentinel (`referee_list_screen.dart:234`) |
| `quantity` | `String` | `quantity` | Defaults `'—'`; rendered as `"{quantity} gm"` unless the sentinel |
| `status` | `String` | `status` | Join/referral status, free text, styled via `_style()` |
| `statusCode` | `int?` | `status_code` | **Parsed but never used anywhere in the UI** — dead field client-side |
| `rewardStatus` | `String` | `reward_status` | Reward disbursement status, free text, styled via the same `_style()` map as `status` |

### `RefereeListData` (`referee_list_service.dart:37-44`)

| Field | Type | Source JSON key | Notes |
|---|---|---|---|
| `count` | `int` | `count` | Used in the summary chip ("N Friends Referred") |
| `results` | `List<RefereeItem>` | `results` | No pagination cursor/page fields present in the model at all |

## Secure Storage / Local Persistence

**None.** Grep-confirmed — no `SecureStorageService`, `flutter_secure_storage`, or `shared_preferences`
usage anywhere in `referral_screen.dart`, `referral_service.dart`, `referee_list_screen.dart`, or
`referee_list_service.dart`. All state is transient (in-memory Riverpod `FutureProvider` cache, cleared
on every screen visit per RULE-REFERRAL-007). The only "persistence-adjacent" behavior is the 60-second
clipboard auto-clear after copying the code (`referral_screen.dart:407-410`), which is OS clipboard
state, not app storage.

## Loading / Error / Empty State Coverage

| Screen | Loading | Error (from thrown exception) | Empty (0 items, no exception) |
|---|---|---|---|
| `ReferralScreen` | `CircularProgressIndicator` (`referral_screen.dart:59`) | Renders as if data were `ReferralData.empty` (`referral_screen.dart:60-61`) — no distinct error UI, no retry | Stats banner hidden if 0/0 (`referral_screen.dart:244`); code card + bullets + how-it-works still render normally with an empty code string |
| `RefereeListScreen` | 5-item shimmer skeleton (`referee_list_screen.dart:51-68`) | Dedicated error UI with Retry button (`referee_list_screen.dart:71-91`) — but per `BUSINESS_RULES.md` RULE-REFERRAL-006, `RefereeListService.fetchList()` never actually throws, so this branch is effectively unreachable in practice | Dedicated "No Referrals Yet" empty-state illustration + copy (`referee_list_screen.dart:94-130`) |

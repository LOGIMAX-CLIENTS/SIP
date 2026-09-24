# Method Index — Referral

Alphabetical by `Class.method`. Private (`_`-prefixed) methods included where they carry business logic
(not pure layout helpers), since the module has no controller layer to hold that logic instead.

---

### `RefereeItem.fromJson(Map<String, dynamic>)` → `RefereeItem`
- **File:line**: `referee_list_service.dart:26-34`
- **Purpose**: Deserializes one referee row. Defaults every string field to `''`/`'—'` and `statusCode`
  to `null` if the key is absent — tolerant of partial server payloads.
- **Callers**: `RefereeListService.fetchList()` via `.map(RefereeItem.fromJson)` (`referee_list_service.dart:70`)

### `RefereeListData` (const constructor + `.empty`)
- **File:line**: `referee_list_service.dart:37-44`
- **Purpose**: Holds `count` (int) + `results` (`List<RefereeItem>`). `.empty` is the zero-state used on
  any parse failure or API error.
- **Callers**: `RefereeListService.fetchList()`, `refereeListProvider`

### `RefereeListScreen._buildEmpty()` / `_buildError()` / `_buildList()` / `_buildSkeleton()`
- **File:line**: `referee_list_screen.dart:94-130`, `71-91`, `133-184`, `51-68`
- **Purpose**: The four `AsyncValue.when` render branches. `_buildError` is reachable only if
  `refereeListProvider`'s future *throws* — which `RefereeListService.fetchList()` never does (it
  catches everything internally, see below) — so this branch is currently dead in practice.
- **Callers**: `RefereeListScreen.build()` (`referee_list_screen.dart:37-43`)

### `RefereeListScreen._RefereeCard._style(String status)` → `_StatusStyle`
- **File:line**: `referee_list_screen.dart:195-228`
- **Purpose**: Maps a lower-cased status string (`disbursed`, `hold`, `pending`, `no reward`, default)
  to a `{bg, fg, icon}` chip style. Used for **both** the join-status chip and the reward-status chip
  (`referee_list_screen.dart:316,319`) — i.e. the same 4-way switch is reused for two conceptually
  different status fields (`item.status` vs `item.rewardStatus`); any status string outside those 4
  values (from either field) silently falls through to the generic grey "default" style.
- **Callers**: `_RefereeCard.build()` (`referee_list_screen.dart:232`)

### `RefereeListScreen._RefereeCard._formatDate(String raw)` → `String`
- **File:line**: `referee_list_screen.dart:415-429`
- **Purpose**: Reformats a `YYYY-MM-DD` string to `DD Mon YYYY` by manual `split('-')` + a hardcoded
  month-name array — no `intl`/`DateFormat` use. Returns the raw string unchanged if the format doesn't
  match (`parts.length != 3`) or on any exception.
- **Callers**: `_RefereeCard.build()` (`referee_list_screen.dart:301`)

### `RefereeListService.fetchList()` → `Future<RefereeListData>`
- **File:line**: `referee_list_service.dart:51-79`
- **Purpose**: `POST referrals/referee-list` with an empty body. Returns `.empty` on: null body,
  non-Map body, `success != true`, non-Map `data`, or any thrown exception (all paths caught,
  `catch (e, st)` at line 75 — never rethrows).
- **Callers**: `refereeListProvider` (`referee_list_service.dart:87-89`)

### `ReferralData.fromJson(Map<String, dynamic>)` → `ReferralData`
- **File:line**: `referral_service.dart:28-53`
- **Purpose**: Deserializes the referral-summary payload. Notably parses `bullet_points` as either a
  list of `{content: "..."}` objects or plain strings (`referral_service.dart:29-40`) — server-driven
  copy for the "Why Refer?" card, with a hardcoded 3-bullet fallback in the screen if the array is empty
  (`referral_screen.dart:264-271`).
- **Callers**: `ReferralService.fetchReferralData()` (`referral_service.dart:90`)

### `ReferralService.fetchReferralData()` → `Future<ReferralData>`
- **File:line**: `referral_service.dart:70-98`
- **Purpose**: `POST users/auth/referral/details` with an empty body. Same empty-on-any-failure pattern
  as `RefereeListService.fetchList()` — returns `ReferralData.empty` on null body, `success == false`,
  non-Map `data`, or any exception (`catch (e, st)` at line 94, never rethrows).
- **Callers**: `referralDataProvider` (`referral_service.dart:105-107`)

### `_ReferralScreenState._buildBody(...)`, `_buildBulletSection(...)`, `_buildHowItWorks()`,
### `_buildPremiumCodeCard(...)`, `_buildStatsRow(...)`, `_buildHeroHeader(...)`, `_buildBullet(...)`
- **File:line**: `referral_screen.dart:235-261`, `264-334`, `487-572`, `337-484`, `575-706`, `77-204`, `206-232`
- **Purpose**: Pure layout builders for the hero header, code card, bullet card, "How It Works" static
  3-step row, and stats banner. `_buildBullet` (line 206) is dead code — defined but never called
  anywhere in the file (the bullet rendering actually used is inline inside `_buildBulletSection`,
  lines 300-330, which duplicates the same row/dot/text structure).
- **Callers**: `build()` and each other (see file for the call graph — cosmetic, not business logic)

### `_ReferralScreenState._shareReferral(String code, String rewardAmount)` → `Future<void>`
- **File:line**: `referral_screen.dart:35-43`
- **Purpose**: Builds a fixed share-text template (emoji + code + hardcoded download link
  `https://startgold.com/download`, **unconfirmed** whether this is the real production download URL —
  no app-config/deep-link constant referenced) and invokes `Share.share(...)` from `share_plus` — opens
  the native OS share sheet (SMS, WhatsApp, email, etc.), no app-specific channel selection logic.
- **Callers**: The "Share" button `onPressed` (`referral_screen.dart:454`)

### `_ReferralScreenState.initState()`
- **File:line**: `referral_screen.dart:26-32`
- **Purpose**: `Future.microtask(() => ref.invalidate(referralDataProvider))` — forces a fresh API call
  every time the screen mounts, bypassing Riverpod's normal cache-until-invalidated behavior for a
  `FutureProvider`.
- **Callers**: Framework (`State` lifecycle)

### `_RefereeListScreenState.initState()`
- **File:line**: `referee_list_screen.dart:20-25`
- **Purpose**: Same pattern as above for `refereeListProvider`.
- **Callers**: Framework (`State` lifecycle)

---

## Coverage Note

All public (non-`_`) methods across the 4 files are documented above (2 model factories, 2 service
methods, 4 Riverpod provider declarations covered in `STATE_ANALYSIS.md` rather than duplicated here).
Widget `build()`/layout-only private methods are covered only where they contain a decision point
(status→style mapping, date formatting, share-text construction) — pure `Container`/`Padding` nesting is
intentionally omitted per `AGENTS.md` §11 (concise, code-specific facts only).

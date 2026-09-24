# Data Flow — Referral

5 end-to-end flows, each with file:line citations at every hop.

---

## Flow 1 — Referral screen load (own code + stats)

```
ReferralScreen mounts
  → initState() [referral_screen.dart:26-32]
      Future.microtask(() => ref.invalidate(referralDataProvider))
      ── forces a fresh fetch even if the provider was already cached from a prior visit
  → build() [referral_screen.dart:47] watches referralDataProvider
  → referralDataProvider [referral_service.dart:105-107] (FutureProvider)
      → ref.read(referralServiceProvider).fetchReferralData()
  → ReferralService.fetchReferralData() [referral_service.dart:70-98]
      → ApiClient().post('users/auth/referral/details', data: {})
      → response.data parsed:
          null           → ReferralData.empty
          success==false → ReferralData.empty
          data is Map    → ReferralData.fromJson(data)  [referral_service.dart:28-53]
          (anything else, or thrown exception) → ReferralData.empty
  → AsyncValue<ReferralData> flows back to build()
      loading → CircularProgressIndicator [referral_screen.dart:59]
      error   → _buildBody(..., ReferralData.empty, [], '') [referral_screen.dart:60-61]
                 (visually identical to a legitimate "0 referrals" response — see MODULE_BRAIN risk #1)
      data    → _buildHeroHeader + _buildBody render:
                  - hero title: server 'title' field if non-empty, else a hardcoded
                    "Invite a friend and earn {rewardText} worth of Gold." [referral_screen.dart:148-181]
                  - code card: data.referralCode [referral_screen.dart:237,387]
                  - bullets: data.bulletPoints if non-empty, else 3 hardcoded fallback strings
                    [referral_screen.dart:264-271]
                  - stats banner only shown if totalReferrals>0 OR totalEarned>0 [referral_screen.dart:244]
```

## Flow 2 — Copy / Share referral code

```
User taps "Copy Code" [referral_screen.dart:404-413]
  → Clipboard.setData(ClipboardData(text: code))
  → Future.delayed(60s) → Clipboard.setData(ClipboardData(text: ''))   // auto-clear
  → AppToast.show(context, 'Referral code copied!', type: success)

User taps "Share" [referral_screen.dart:453-454]
  → _shareReferral(code, rewardAmount) [referral_screen.dart:35-43]
      builds text: "🌟 Join me on StartGold and earn ₹{reward} in free Digital Gold!\n\n
                    Use my referral code: {code}\n\nDownload now 👇\nhttps://startgold.com/download"
      → Share.share(text, subject: 'Invite to StartGold')   // share_plus package
      → Native OS share sheet (WhatsApp/SMS/email/etc.) — no in-app tracking of which channel was used
```

## Flow 3 — Referee list load

```
RefereeListScreen mounts (pushed from ReferralScreen's stats banner, see Flow 5)
  → initState() [referee_list_screen.dart:20-25]
      Future.microtask(() => ref.invalidate(refereeListProvider))
  → build() watches refereeListProvider [referee_list_screen.dart:29]
  → refereeListProvider [referee_list_service.dart:87-89]
      → ref.read(refereeListServiceProvider).fetchList()
  → RefereeListService.fetchList() [referee_list_service.dart:51-79]
      → ApiClient().post('referrals/referee-list', data: {})
      → parsed to RefereeListData{count, results: List<RefereeItem>}
        or RefereeListData.empty on any failure/malformed response (never throws)
  → AsyncValue<RefereeListData> → build():
      loading        → _buildSkeleton() — 5 shimmer placeholder cards [referee_list_screen.dart:51-68]
      error           → _buildError() — dead in practice, see METHOD_INDEX
      data, empty     → _buildEmpty() — "No Referrals Yet" illustration [referee_list_screen.dart:94-130]
      data, non-empty → _buildList(data) — summary chip + ListView.separated of _RefereeCard
                          [referee_list_screen.dart:133-184]
  → Each _RefereeCard [referee_list_screen.dart:188-437]:
      - avatar: first letter of item.referee, uppercased [referee_list_screen.dart:266-267]
      - join-status chip: _style(item.status)
      - reward-status chip: _style(item.rewardStatus)   // same 4-way switch reused for both fields
      - reward badge (gold/silver gradient) shown only if item.reward != '—' [referee_list_screen.dart:234,328]
      - date: _formatDate(item.referralDate) — manual YYYY-MM-DD → "DD Mon YYYY" parse
```

## Flow 4 — Signup-time referral-code entry (cross-module: `auth`/`registration` → server)

This is the **other half** of the loop — this module never writes a referral code, only reads the
outcome. Full detail in `CROSS_MODULE_MAP.md`.

```
User on RegistrationScreen types into "Referral Code (Optional)" field
  [lib/features/auth/registration/registration_screen.dart:304-311, controller at line 36]
  → user taps Continue → _handleContinue-equivalent flow
  → AuthService.registerCheck(..., referralCode: _referralController.text.trim())
      [lib/features/auth/registration/registration_screen.dart:532-539]
      → POST users/auth/register-check
        { mobile, full_name, email, dob, referral_code, temp_token, device_id, device_type }
        [lib/core/services/auth_service.dart:180-197, field mapped at line 193]
      → success==true → Navigator.pushReplacementNamed(AppRouter.mpinCreation,
                           arguments: {..., 'referralCode': _referralController.text.trim(), ...})
                           [registration_screen.dart:544-556]
      → success==false → generic error toast (no field-specific "invalid referral code" messaging
                           visible client-side — server error message shown verbatim/parsed generically)
                           [registration_screen.dart:557-574]

PinCreationScreen receives widget.referralCode [pin_creation_screen.dart:28,36]
  → user sets + confirms PIN → _handleSetPin() [pin_creation_screen.dart:392+]
  → Step 1 (only if !_registerComplete): AuthController.register(..., referralCode: widget.referralCode)
      [pin_creation_screen.dart:405-414]
      → AuthNotifier.register(...) [lib/core/services/auth_service.dart:519-540ish]
          → AuthService.register(...) [auth_service.dart:128-147]
              → POST users/auth/register
                { mobile, full_name, email, dob, referral_code, temp_token, device_id, device_type }
                (field mapped at auth_service.dart:143)
              → 'auth/register' matches AppConfig.encryptedEndpoints [app_config.dart:52] →
                 entire request payload (including referral_code) is RSA-OAEP-SHA256 encrypted by
                 ApiClient's interceptor before transmission (endpoint-level, not per-field, encryption
                 — see api_interceptor.dart)
  → Step 2: sets MPIN via mpin/create — outside this module's scope

Server-side: reward creation/crediting logic for the referral is NOT visible in this Flutter codebase
(backend concern) — this module only ever reads the aggregated result later via Flow 1/3.
```

## Flow 5 — Navigating between the two referral screens

```
ReferralScreen: user taps the stats banner (Friends Referred card)
  [referral_screen.dart:245-249] — only tappable if data.totalReferrals > 0
  → Navigator.pushNamed(context, AppRouter.refereeList)   [referral_screen.dart:247]
  → RefereeListScreen mounts → Flow 3

RefereeListScreen back button: uses the default AppBar-less Column/GradientHeader
  — GradientHeader presumably provides its own back affordance (shared/widgets/gradient_header.dart,
  not read in full for this brain — cross-module, see CROSS_MODULE_MAP.md); back navigation behavior
  itself was not independently re-verified line-by-line, marked unconfirmed.
```

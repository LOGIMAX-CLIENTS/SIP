---
module: Home
last_updated: 2026-08-19
---

# Home — Method Index

Alphabetical by class, then by method. `file:line` is the definition site. "Callers" lists in-module callers
only (cross-module callers noted where known).

## `CommodityPortfolio` / `PortfolioData` — see `core/providers/portfolio_provider.dart` (documented in `CROSS_MODULE_MAP.md`, not owned by Home)

## `ComplianceItem` — `models/home_dashboard.dart`
- `ComplianceItem.fromJson(json)` — `home_dashboard.dart:175` — called by `FooterInfo.fromJson` (`:158-161`)

## `CountdownOfferExisting` — `widgets/countdown_offer_existing.dart`
- `build(context)` — `:24` — called by `CountdownOfferWidget.build` (`countdown_offer_widget.dart:29`)
- `_splitTextAndNumbers(input)` — `:68` — called by `_buildProgressCard` (`:242`)
- `_buildBadgeBanner()` — `:85` — called by `build` (`:56`)
- `_buildProgressCard(context)` — `:117` — called by `build` (`:60`)
- `_buildStatColumn(label, value)` — `:281` — called by `_buildProgressCard` (`:196,207`)
- `_buildCtaButton(context)` — `:305` — called by `_buildProgressCard` (`:270`); navigates to `AppRouter.instantSaving`
- `_buildAboutOfferRow(context)` — `:343` — called by `_buildProgressCard` (`:274`)
- `_showOfferBenefitsSheet(context)` — `:369` — called by `_buildAboutOfferRow` tap handler (`:345`); pushes `OfferWebViewScreen`

## `CountdownOfferNew` (`_CountdownOfferNewState`) — `widgets/countdown_offer_new.dart`
- `initState()` — `:38` — seeds `_days/_hours/_minutes/_seconds` from `widget.offer.remaining*`, calls `_startTimer()`
- `_startTimer()` — `:47` — `Timer.periodic(1s)` local countdown decrement, **not** re-synced to server; cancels itself at zero (`:65-67`)
- `dispose()` — `:73` — cancels `_timer`
- `_isExpired` (getter) — `:78`
- `_splitTextAndNumbers(input)` — `:83` — used for mixed number/text styling (Lora for digits, PlayfairDisplay for text)
- `build(context)` — `:101` — returns `SizedBox.shrink()` if `_isExpired`
- `_buildBadgeBanner()` — `:296`
- `_buildCountdownCard()` — `:330`
- `_buildTimeUnit(value, label)` / `_buildTimeSeparator()` — `:409` / `:445`
- `_buildOfferDescription()` — `:468` — API-driven `descriptionTitle`/`descriptionBody`
- `_buildBulletSection()` — `:495` — reward % / daily penalty % bullets
- `_buildCtaButton()` — `:595` — navigates to `AppRouter.instantSaving`
- `_showOfferBenefitsSheet(context)` — `:640` — pushes `OfferWebViewScreen` with `offer.webviewUrl` (no-op if null/empty)

## `CountdownOfferResponse` — `models/countdown_offer_model.dart`
- `CountdownOfferResponse.fromJson(json)` — `:21` — called by `HomeService.getCountdownOffer()` (`core/services/home_service.dart:32`)
- `CountdownOfferResponse.disabled()` — `:58` — fallback for `enabled:false`/malformed/error responses

## `CountdownOfferWidget` — `widgets/countdown_offer_widget.dart`
- `build(context, ref)` — `:21` — watches `countdownOfferProvider`; routes to `CountdownOfferNew`/`CountdownOfferExisting`/`SizedBox.shrink()`
- `_buildShimmer()` — `:43` — loading-state placeholder via `AppLoaders.sectionLoader`

## `ExistingCustomerOffer` — `models/countdown_offer_model.dart`
- `ExistingCustomerOffer.fromJson(json)` — `:151` — called by `CountdownOfferResponse.fromJson` (`:37-48`, with `webview_url` injection fallback from root JSON)

## `FooterInfo` — `models/home_dashboard.dart`
- `FooterInfo.fromJson(json)` — `:154` — called by `HomeDashboard.fromJson` (`:25-27`)

## `HomeDashboard` — `models/home_dashboard.dart`
- `HomeDashboard.fromJson(json)` — `:14` — called by `HomeService.getHomeDashboard()` (`core/services/home_service.dart:13`)

## `HomeScreen` (`_HomeScreenState`) — `home_screen.dart`
- `initState()` — `:41` — post-frame callback refreshes unread notification count
- `build(context)` — `:50` — the whole dashboard: watches 7 providers, sets up 3 `ref.listen` side-effect chains (market-reopen timer restart, race-condition rate re-lock, tab-refresh), returns `CustomScrollView`
- `_buildDashboardContent(context, ref, isDark, dashboard)` — `:394` — renders rate-history + invest + discover + learn + support sections
- `_buildDashboardError(ref, isDark, error)` — `:527` — retry card, `onPressed` invalidates `homeDashboardProvider`
- `_buildHomeScreenSkeleton(isDark)` — `:634`
- `_buildInvestBlock(block)` — `:692` — renders asset or network image for one API-driven invest card
- `_investBlockPlaceholder()` — `:717`
- `_buildInvestContent(section)` — `:736` — falls back to `_buildStaticInvestBlocks()` if `section.blocks` empty
- `_buildStaticInvestBlocks()` — `:753` — includes `MicroSavingsBanner`, navigates to `AppRouter.autoSavings` on swipe
- `_buildStaticInvestCard(imagePath, {title, subtitle})` — `:772`
- `_buildSectionHeader(title, isDark)` — `:830`
- `_buildDiscoverSection(isDark)` — `:843` — 3 static tiles: Cash Withdrawal → `AppRouter.withdrawal`, Refer & Earn → `AppRouter.referral`, Auto Saving → `AppRouter.autoSavings`
- `_buildSupportSection(isDark)` — `:913` — "Contact Us" → `AppRouter.contact`
- `_buildFooterInfo(isDark, info)` — `:983`
- `_buildPremiumHeader(...)` — `:1070` — computes displayed rate (locked vs. live), builds `SliverPersistentHeader` with `PremiumHomeHeader`
- `_formatIndianRate(rate)` — `:1122` — Indian digit grouping (has dead/unused `buffer` loop at `:1132-1136`, real output built by second loop `:1138-1144`)
- `_buildGrowthStreakCard(isDark, history)` — `:1150` — "Invest Now" button sets `selectedTabProvider.notifier.state = 1`
- `_buildChartDataPoint(label, {backgroundColor, textColor})` — `:1256`
- `_buildPortfolioOverview(isDark, data, selected, market, isCurrentMarketClosed)` — `:1281` — client-side recompute of `currentValue`/`returns`/`returnsPct` when API value is `0` but balance/live-rate are non-zero (`:1296-1302`)
- `_buildCommodityToggle(selected, isMarketClosed)` — `:1475` — renders pill toggle + referral message + market-closed banner
- `_buildCommodityPillTab({label, isActive, isGoldTab, onTap})` — `:1591`
- `_buildPortfolioSkeleton(isDark)` — `:1658`
- `_buildPortfolioError(isDark)` — `:1715`
- `_buildNewCustomerBanner(context, selected, isCurrentMarketClosed)` — `:1719` — shown instead of portfolio card when `isNewUser` or `data.isNewCustomer`

## `InvestBlock` / `InvestSection` — `models/home_dashboard.dart`
- `InvestBlock.fromJson(json)` — `:92`
- `InvestSection.fromJson(json)` — `:75`

## `LearnCarousel` (`_LearnCarouselState`) — `widgets/learn_carousel.dart`
- `initState()` — `:34` — starts `_progressController` + `_startAutoSlide()`
- `dispose()` — `:48`
- `_startAutoSlide()` — `:55` — `Timer.periodic(autoSlideSeconds)` → `_nextPage()`
- `_nextPage()` — `:64` — animates `PageController` to `(current+1) % images.length`
- `_onPageChanged(page)` — `:75` — resets auto-slide timer on manual swipe
- `build(context)` — `:82` — returns `SizedBox.shrink()` if `images` empty
- `_buildImage(path)` — `:192` — dispatches `Image.network` vs `Image.asset` by URL prefix

## `LearningBanner` / `LearningSection` — `models/home_dashboard.dart`
- `LearningBanner.fromJson(json)` — `:129`
- `LearningSection.fromJson(json)` — `:105`

## `MicroSavingsBanner` (`_MicroSavingsBannerState`) — `widgets/micro_savings_banner.dart`
- `initState()` — `:34` — sets up `_hintController` (repeating hint animation) and `_chevronController`
- `dispose()` — `:63`
- `_onDragStart(details)` — `:70` — stops hint animation
- `_onDragUpdate(details)` — `:75` — clamps `_dragOffset` to `[0, _maxDrag]`
- `_onDragEnd(details)` — `:82` — if drag ≥ 70% of `_maxDrag`, fires `widget.onSwipeComplete()` (in `HomeScreen`, navigates to `AppRouter.autoSavings`), then auto-resets after 600ms
- `build(context)` — `:106`
- `_buildSwipeTrack()` — `:188`

## `NewCustomerOffer` — `models/countdown_offer_model.dart`
- `NewCustomerOffer.fromJson(json)` — `:103` — called by `CountdownOfferResponse.fromJson` (`:32-36`)

## `OfferWebViewScreen` (`_OfferWebViewScreenState`) — `widgets/offer_webview_screen.dart`
- `initState()` — `:38` — web: opens browser tab; native: `_initWebView()`
- `_initWebView()` — `:51` — registers Android/iOS WebView platform impl, sets up `NavigationDelegate` + `FlutterChannel` JS bridge
- `_openInBrowser()` — `:92` — web-only fallback via `url_launcher`
- `_handleDeepLink(url)` — `:100` — intercepts `startgold://` scheme; `instantSaving` deep link pops and pushes `/instantSaving`
- `build(context)` — `:109`
- `_buildFooterButton()` — `:158` — "Start Investing" CTA → `AppRouter.instantSaving`

## `PremiumHomeHeader` (`SliverPersistentHeaderDelegate`) — `home_screen.dart`
- `build(context, shrinkOffset, overlapsContent)` — `:1864` — greeting, notification bell + badge (→ `AppRouter.notifications`), live-rate pill
- `_buildLiveRatePill(rate, isMarketClosed)` — `:1968` — renders `_LiveBadge` or `_ClosedBadge`
- `_buildActionIcon(isDark, icon, [color])` — `:2031`
- `maxExtent` / `minExtent` (getters) — `:2050` / `:2053` — both `statusBarHeight + 125.h` (fixed-height pinned header)
- `shouldRebuild(oldDelegate)` — `:2057` — always `true`

## `RateHistory` — `models/home_dashboard.dart`
- `RateHistory.fromJson(json)` — `:49` — `_parseRate` local helper handles both string and numeric API values (`:51-54`)

## `_ClosedBadge` (`_ClosedBadgeState`) — `home_screen.dart:2164`
- `initState()` / `dispose()` / `build(context)` — `:2176` / `:2185` / `:2191` — amber pulsing "CLOSED" pill, static bars

## `_LiveBadge` (`_LiveBadgeState`) — `home_screen.dart:2063`
- `initState()` / `dispose()` / `build(context)` — `:2075` / `:2085` / `:2090` — red pulsing "LIVE" pill, animated wave bars

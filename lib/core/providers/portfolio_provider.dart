import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/portfolio_service.dart';
import 'commodity_provider.dart';
import 'user_provider.dart';

class CommodityPortfolio {
  final double totalInvested;
  final double currentValue;
  final double returns;
  final double returnsPercentage;
  final double balance; // in grams
  final bool hasActiveAccount;

  CommodityPortfolio({
    required this.totalInvested,
    required this.currentValue,
    required this.returns,
    required this.returnsPercentage,
    required this.balance,
    required this.hasActiveAccount,
  });

  factory CommodityPortfolio.empty() => CommodityPortfolio(
        totalInvested: 0,
        currentValue: 0,
        returns: 0,
        returnsPercentage: 0,
        balance: 0,
        hasActiveAccount: false,
      );
}

class PortfolioData {
  final CommodityPortfolio summary;
  final bool isNewCustomer;

  PortfolioData({
    required this.summary,
    required this.isNewCustomer,
  });

  factory PortfolioData.empty() => PortfolioData(
        summary: CommodityPortfolio.empty(),
        isNewCustomer: true,
      );
}

class PortfolioNotifier extends StateNotifier<AsyncValue<PortfolioData>> {
  final PortfolioService _portfolioService;
  final String _idMetal;
  final String _idCustomer;

  PortfolioNotifier(this._portfolioService, this._idMetal, this._idCustomer)
      : super(
          // Start with cached data if available to prevent flicker
          // when switching between Gold and Silver tabs.
          // 1st priority: exact metal cache, 2nd: any previous data
          _portfolioCache.containsKey(_idMetal)
              ? AsyncValue.data(_portfolioCache[_idMetal]!)
              : _portfolioCache.isNotEmpty
                  ? AsyncValue.data(_portfolioCache.values.last)
                  : const AsyncValue.loading(),
        ) {
    fetchPortfolio();
  }

  Future<void> fetchPortfolio() async {
    if (_idCustomer.isEmpty) {
      state = AsyncValue.data(PortfolioData.empty());
      return;
    }
    // Preserve previous data during refresh to prevent card flicker
    // when switching between Gold and Silver tabs.
    final prev = state.valueOrNull;
    if (prev == null) {
      state = const AsyncValue.loading();
    }
    try {
      final data =
          await _portfolioService.getPortfolioSummary(_idMetal, _idCustomer);
      _portfolioCache[_idMetal] = data;
      state = AsyncValue.data(data);
    } catch (e, st) {
      // If we had previous data, keep it visible with the error
      if (prev != null) {
        state = AsyncValue.data(prev);
      } else {
        state = AsyncValue.error(e, st);
      }
    }
  }
}

/// In-memory cache of portfolio data keyed by metal ID.
/// Prevents loading-skeleton flicker when toggling Gold ↔ Silver
/// because the autoDispose provider is re-created on each switch.
final Map<String, PortfolioData> _portfolioCache = {};

final portfolioProvider =
    StateNotifierProvider.autoDispose<PortfolioNotifier, AsyncValue<PortfolioData>>((ref) {
  final service = ref.watch(portfolioServiceProvider);
  final userProfile = ref.watch(userProvider);

  final String idCustomer = userProfile?.id ?? '';
  // Reads id_metal dynamically from the API commodity list
  final String idMetal = ref.watch(selectedMetalIdProvider);

  return PortfolioNotifier(service, idMetal, idCustomer);
});


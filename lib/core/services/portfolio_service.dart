import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../providers/portfolio_provider.dart';

class PortfolioService {
  final ApiClient _apiClient = ApiClient();

  Future<PortfolioData> getPortfolioSummary(
      String idMetal, String idCustomer) async {
    try {
      final response = await _apiClient.post(
        'portfolio/summary',
        data: {
          'id_metal': idMetal,
          //'id_customer': idCustomer,
        },
      );
      if (response.data != null && response.data['success'] == true) {
        final data = response.data['data'] ?? {};

        final invested = double.tryParse(data['total_invested']?.toString() ?? '0') ?? 0.0;
        final value = double.tryParse(data['current_value_inr']?.toString() ?? '0') ?? 0.0;
        final balance = double.tryParse(data['total_holdings_grams']?.toString() ?? '0') ?? 0.0;
        final withdrawable = double.tryParse(data['withdrawable_inr']?.toString() ?? '');

        final summary = CommodityPortfolio(
          totalInvested: invested,
          currentValue: value,
          returns: value - invested,
          returnsPercentage: double.tryParse(data['growth_percentage']?.toString() ?? '0') ?? 0.0,
          balance: balance,
          hasActiveAccount: balance > 0 || invested > 0,
          withdrawableInr: withdrawable,
        );

        return PortfolioData(
          summary: summary,
          isNewCustomer: invested == 0 && balance == 0,
        );
      }
      return PortfolioData.empty();
    } catch (e) {
      return PortfolioData.empty();
    }
  }
}

final portfolioServiceProvider =
    Provider<PortfolioService>((ref) => PortfolioService());

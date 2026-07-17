import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/history_models.dart';
import '../models/history_filter_options_model.dart';
import '../services/history_service.dart';
import '../../../core/providers/user_provider.dart';

final historyServiceProvider = Provider<HistoryService>((ref) => HistoryService());

final historyProvider = FutureProvider<HistoryResponse>((ref) async {
  final user = ref.read(userProvider);
  if (user == null) throw Exception('User not logged in');

  return ref.read(historyServiceProvider).getTransactionHistory(
    customerId: user.id,
  );
});

/// Dynamic filter option set (commodities, transaction types, statuses)
/// for the Transaction History filter sheet. Mirrors [sipConfigProvider]'s
/// "fetch config on screen load" pattern.
final historyFilterOptionsProvider =
    FutureProvider.autoDispose<HistoryFilterOptions>((ref) async {
  final user = ref.read(userProvider);
  if (user == null) throw Exception('User not logged in');

  return ref.read(historyServiceProvider).getFilterOptions(
        customerId: user.id,
      );
});

final transactionDetailsProvider = FutureProvider.family<TransactionDetailResponse, String>((ref, transactionId) async {
  final user = ref.read(userProvider);
  if (user == null) throw Exception('User not logged in');

  return ref.read(historyServiceProvider).getTransactionDetails(
    customerId: user.id,
    transactionId: transactionId,
  );
});

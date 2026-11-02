import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/history/controller/history_controller.dart';
import 'package:startgold/features/history/models/history_models.dart';
import 'package:startgold/features/history/models/transaction_filter.dart';
import 'package:startgold/features/history/services/history_service.dart';

/// Counts transactions/history calls. `implements` rather than `extends`, so
/// no real ApiClient is built.
class FakeHistoryService implements HistoryService {
  int calls = 0;
  Completer<HistoryResponse>? pending;
  Object? failWith;

  @override
  Future<HistoryResponse> getTransactionHistory({
    required String customerId,
    String? metalType,
    int page = 1,
    int limit = 20,
    String? commodity,
    String? transactionType,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) {
    calls++;
    if (failWith != null) return Future.error(failWith!);
    if (pending != null) return pending!.future;
    return Future.value(HistoryResponse.fromJson(const {}));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<HistoryNotifier> loaded(FakeHistoryService service) async {
  final notifier = HistoryNotifier(service, 'customer-1');
  await Future<void>.delayed(Duration.zero);
  return notifier;
}

void main() {
  test('re-entering History right after a load reuses page 1', () async {
    final service = FakeHistoryService();
    final notifier = await loaded(service);
    expect(service.calls, 1);

    await notifier.refreshIfStale();
    await notifier.refreshIfStale();
    expect(service.calls, 1);

    await notifier.refresh();
    expect(service.calls, 2, reason: 'a manual refresh always fetches');
  });

  test('a refresh while page 1 is in flight joins that request', () async {
    final service = FakeHistoryService()..pending = Completer();
    final notifier = HistoryNotifier(service, 'customer-1');
    final first = notifier.refresh();
    final second = notifier.refresh();
    expect(service.calls, 1);

    service.pending!.complete(HistoryResponse.fromJson(const {}));
    await Future.wait([first, second]);
    expect(notifier.state.page, 1);
  });

  test('a new filter is fetched even while page 1 is in flight', () async {
    final service = FakeHistoryService()..pending = Completer();
    final notifier = HistoryNotifier(service, 'customer-1');
    notifier.applyFilter(const TransactionFilter(status: 'success'));
    expect(service.calls, 2);
    service.pending!.complete(HistoryResponse.fromJson(const {}));
  });

  test('refresh backs off after TOO_MANY_REQUESTS', () async {
    final service = FakeHistoryService()
      ..failWith = const HistoryRateLimitedException(
          'Too many attempts. Please wait 1 minutes before trying again.');
    final notifier = await loaded(service);
    expect(service.calls, 1);
    expect(notifier.state.error, startsWith('Too many attempts'));

    await notifier.refresh();
    await notifier.refreshIfStale();
    expect(service.calls, 1);
  });
}

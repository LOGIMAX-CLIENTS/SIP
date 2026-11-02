import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/core/services/notification_service.dart';
import 'package:startgold/core/utils/timed_list_cache.dart';

/// `implements` rather than `extends`, so no real ApiClient is built.
class FakeNotificationService implements NotificationService {
  int calls = 0;
  Completer<int>? pending;

  @override
  Future<int> fetchUnreadCount() {
    calls++;
    return pending?.future ?? Future.value(4);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TimedListCache', () {
    test('reuses a fresh list and shares an in-flight fetch', () async {
      final cache = TimedListCache<List<int>>(const Duration(minutes: 1));
      var calls = 0;
      final pending = Completer<List<int>>();
      Future<List<int>> fetch() {
        calls++;
        return pending.future;
      }

      final a = cache.get('1', fetch);
      final b = cache.get('1', fetch);
      pending.complete([10, 20]);
      expect(await a, [10, 20]);
      expect(await b, [10, 20]);
      expect(await cache.get('1', fetch), [10, 20]);
      expect(calls, 1);
    });

    test('keys are separate and empty results are not cached', () async {
      final cache = TimedListCache<List<int>>(const Duration(minutes: 1));
      var calls = 0;
      Future<List<int>> empty() async {
        calls++;
        return <int>[];
      }

      await cache.get('1', empty);
      await cache.get('1', empty);
      await cache.get('3', empty);
      expect(calls, 3);
    });

    test('a stale list is fetched again', () async {
      final cache = TimedListCache<List<int>>(Duration.zero);
      var calls = 0;
      Future<List<int>> fetch() async => [++calls];

      await cache.get('1', fetch);
      expect(await cache.get('1', fetch), [2]);
    });
  });

  group('refreshUnreadCount', () {
    test('Home load asking three times makes one call', () async {
      final service = FakeNotificationService()..pending = Completer();
      final notifier = NotificationNotifier(service);
      final calls = [
        notifier.refreshUnreadCount(),
        notifier.refreshUnreadCount(),
        notifier.refreshUnreadCount(),
      ];
      service.pending!.complete(4);
      await Future.wait(calls);
      expect(service.calls, 1);
      expect(notifier.state.unreadCount, 4);

      await notifier.refreshUnreadCount();
      expect(service.calls, 1, reason: 'count is still fresh');
    });

    test('force always fetches', () async {
      final service = FakeNotificationService();
      final notifier = NotificationNotifier(service);
      await notifier.refreshUnreadCount();
      await notifier.refreshUnreadCount(force: true);
      expect(service.calls, 2);
    });
  });
}

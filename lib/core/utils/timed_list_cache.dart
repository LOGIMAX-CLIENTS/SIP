/// Per-key cache for lists that change rarely. A value is reused for
/// [maxAge], and concurrent requests for the same key share one fetch.
/// Empty lists — what the shared-service fetchers return on any failure —
/// are never cached.
class TimedListCache<T extends List<Object?>> {
  final Duration maxAge;
  final Map<String, ({DateTime at, T value})> _values = {};
  final Map<String, Future<T>> _inFlight = {};

  TimedListCache(this.maxAge);

  Future<T> get(String key, Future<T> Function() fetch) {
    final cached = _values[key];
    if (cached != null && DateTime.now().difference(cached.at) < maxAge) {
      return Future.value(cached.value);
    }
    return _inFlight[key] ??= fetch().then((value) {
      if (value.isNotEmpty) _values[key] = (at: DateTime.now(), value: value);
      return value;
    }).whenComplete(() {
      // A block body: an arrow would hand the removed future back to
      // whenComplete, which would then wait on itself.
      _inFlight.remove(key);
    });
  }
}

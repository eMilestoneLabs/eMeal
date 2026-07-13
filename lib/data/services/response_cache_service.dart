import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stale-while-revalidate (SWR) cache for read-only API responses.
///
/// Lets a screen paint the last-known data **instantly** from local storage
/// while a fresh network fetch runs in the background — so the app feels
/// instant even on a high-latency connection (e.g. a distant origin). The
/// fresh network result always overwrites the cached one, so data stays correct.
///
/// Design:
///   • Purely **additive** — callers opt in; nothing else changes.
///   • **Best-effort** — every method swallows its own errors, so a cache
///     problem can never break a feature.
///   • Read-only data only — never use for write flows (attendance marking,
///     billing actions, auth). Keys should be scoped (org/group/user) by the
///     caller so one account never reads another's cached data.
///
/// Storage: JSON under a namespaced `shared_preferences` key.
class ResponseCacheService {
  ResponseCacheService._();

  static final ResponseCacheService instance = ResponseCacheService._();

  static const String _prefix = 'swr:';
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Returns the decoded JSON cached under [key], or null if absent/corrupt.
  /// If [maxAge] is given and the entry is older than it, returns null so the
  /// caller never shows badly-stale data (it falls back to a fresh fetch).
  Future<dynamic> read(String key, {Duration? maxAge}) async {
    try {
      final raw = (await _store).getString('$_prefix$key');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      // New format: {'__ts': ms, '__v': value}. Legacy raw values pass through.
      if (decoded is Map &&
          decoded.containsKey('__ts') &&
          decoded.containsKey('__v')) {
        if (maxAge != null && decoded['__ts'] is int) {
          final age = DateTime.now().millisecondsSinceEpoch -
              (decoded['__ts'] as int);
          if (age > maxAge.inMilliseconds) return null;
        }
        return decoded['__v'];
      }
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Pass 13 (FR-OFF-006): when the entry under [key] was written, or null.
  /// Screens use this to show a "last updated" freshness badge while painting
  /// stale-while-revalidate data.
  Future<DateTime?> readTimestamp(String key) async {
    try {
      final raw = (await _store).getString('$_prefix$key');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['__ts'] is int) {
        return DateTime.fromMillisecondsSinceEpoch(decoded['__ts'] as int);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Persists [jsonEncodable] under [key] with a timestamp. Best-effort.
  Future<void> write(String key, Object? jsonEncodable) async {
    try {
      final wrapped = {
        '__ts': DateTime.now().millisecondsSinceEpoch,
        '__v': jsonEncodable,
      };
      await (await _store).setString('$_prefix$key', jsonEncode(wrapped));
    } catch (_) {
      /* best-effort: a failed cache write must never surface to the user */
    }
  }

  // ── Modular cache-first helpers ─────────────────────────────────────────────
  // Encapsulate the read→parse and serialize→write boilerplate so providers
  // stay DRY. All are atomic + best-effort (never throw, never partial).

  /// Reads a cached JSON list and maps each element via [fromJson].
  /// Returns `[]` on miss / corrupt / expired.
  Future<List<T>> readList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson, {
    Duration? maxAge,
  }) async {
    final cached = await read(key, maxAge: maxAge);
    if (cached is List) {
      try {
        return cached
            .whereType<Map<String, dynamic>>()
            .map(fromJson)
            .toList();
      } catch (_) {/* corrupt cache → ignore */}
    }
    return <T>[];
  }

  /// Like [readList] but distinguishes a cache MISS (null) from a genuinely
  /// cached EMPTY list (`[]`). Providers use this so an account whose
  /// last-known answer is "nothing yet" still paints its empty state
  /// instantly (stale-while-revalidate) instead of blocking on the network
  /// behind a skeleton on every tap — the "new account feels slow" root cause.
  Future<List<T>?> readListOrNull<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson, {
    Duration? maxAge,
  }) async {
    final cached = await read(key, maxAge: maxAge);
    if (cached is List) {
      try {
        return cached
            .whereType<Map<String, dynamic>>()
            .map(fromJson)
            .toList();
      } catch (_) {/* corrupt cache → treat as miss */}
    }
    return null;
  }

  /// Writes a list of models as JSON (each via [toJson]). Fire-and-forget.
  Future<void> writeList<T>(
    String key,
    List<T> items,
    Map<String, dynamic> Function(T) toJson,
  ) =>
      write(key, items.map(toJson).toList());

  /// Reads + maps a single cached object via [fromJson]. Null on miss/corrupt.
  Future<T?> readObject<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson, {
    Duration? maxAge,
  }) async {
    final cached = await read(key, maxAge: maxAge);
    if (cached is Map<String, dynamic>) {
      try {
        return fromJson(cached);
      } catch (_) {/* corrupt cache → ignore */}
    }
    return null;
  }

  /// Removes a single cached entry.
  Future<void> remove(String key) async {
    try {
      await (await _store).remove('$_prefix$key');
    } catch (_) {/* ignore */}
  }

  /// Removes expired + corrupt SWR entries. Self-heals after a bad write and
  /// bounds the growth of date-keyed caches (e.g. per-day attendance): any entry
  /// older than [maxAge] by its stored timestamp, or that fails to decode, is
  /// dropped. Legacy/untimestamped entries are left untouched. Best-effort —
  /// never throws. Call fire-and-forget at startup.
  Future<void> prune(Duration maxAge) async {
    try {
      final p = await _store;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        final raw = p.getString(k);
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map &&
              decoded['__ts'] is int &&
              now - (decoded['__ts'] as int) > maxAge.inMilliseconds) {
            await p.remove(k);
          }
        } catch (_) {
          await p.remove(k); // corrupt JSON -> drop it (self-heal)
        }
      }
    } catch (_) {/* best-effort: pruning must never break startup */}
  }

  /// Clears every SWR-cached entry — call on logout so a new account never
  /// sees a previous account's cached data.
  Future<void> clear() async {
    try {
      final p = await _store;
      for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
        await p.remove(k);
      }
    } catch (_) {/* ignore */}
  }
}

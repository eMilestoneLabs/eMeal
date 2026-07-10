import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// CrashReporterService — turns uncaught Flutter/async errors into structured
/// crash reports POSTed to the backend's `/telemetry/client-crashes` sink
/// (structured logs → Loki/Grafana), closing the "crash telemetry: flag present,
/// no reporter wired" gap **without** pulling in Sentry or any third-party SaaS.
///
/// Design guarantees (why this is safe to add to a certified build):
///   • **Additive & opt-in** — does nothing unless [EnvConfig.enableCrashReporting]
///     is true (on in staging/prod, off in dev). Installing the handlers CHAINS
///     onto any existing one, so nothing already wired is lost.
///   • **Can never crash the app** — every path is wrapped; a telemetry failure
///     is swallowed. The error handlers still forward to Flutter's default
///     presentation so the red screen / logging behaviour is unchanged.
///   • **Offline-durable** — a report that fails to send (no network) is buffered
///     in `shared_preferences` (bounded ring, oldest dropped) and flushed on the
///     next launch, so crashes on a dead link are not lost.
///   • **Quiet** — identical errors are de-duped within a session and a per-session
///     send cap prevents a crash-loop from flooding the network or the logs. The
///     server independently throttles (30/min per IP) and caps its own logging.
///   • **Privacy** — only a redacted error/stack + coarse app/device context is
///     sent; bearer tokens and long digit runs are scrubbed before send. No PII,
///     no auth token, no request bodies.
class CrashReporterService {
  CrashReporterService._();

  static final CrashReporterService instance = CrashReporterService._();

  static const String _endpoint = '/telemetry/client-crashes';
  static const String _bufferKey = 'crash:pending';
  static const int _maxBuffered = 20; // ring buffer ceiling
  static const int _maxPerSession = 25; // stop a crash-loop from flooding
  static const int _maxErrorChars = 2000;
  static const int _maxStackChars = 8000;

  /// App semantic version. Injected at build time
  /// (`--dart-define=APP_VERSION=1.0.0+1`); falls back to the pubspec value so a
  /// plain `flutter build` still reports something meaningful.
  static const String _appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0+1');

  /// Optional hook the app can set so reports carry the current route/screen
  /// (e.g. `() => router.currentRoute`). Kept as an injectable callback so the
  /// reporter has ZERO coupling to the router and can never fail to compile if
  /// the routing API changes. Guarded at call time.
  String? Function()? routeResolver;

  bool _installed = false;
  int _sentThisSession = 0;
  final Set<String> _seenSignatures = <String>{};
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// Installs the global error handlers. Idempotent. No-op when crash reporting
  /// is disabled for the active environment. Call once, early in bootstrap.
  void initialize() {
    if (_installed || !EnvConfig.current.enableCrashReporting) return;
    _installed = true;

    // 1) Framework build/layout/paint errors + anything routed through
    //    FlutterError.reportError. Chain the previous handler so Flutter's
    //    default console/red-screen presentation is preserved.
    final previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      try {
        unawaited(_capture(
          error: details.exceptionAsString(),
          stack: details.stack?.toString(),
          kind: 'flutter',
          fatal: false,
        ));
      } catch (_) {/* telemetry must never break error handling */}
      if (previousFlutterOnError != null) {
        previousFlutterOnError(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    // 2) Uncaught ASYNC errors that escape to the platform dispatcher (the
    //    modern replacement for wrapping runApp in runZonedGuarded — works in
    //    Flutter 3.7+). Returning true = handled; we return the previous
    //    handler's verdict (default false) so behaviour is otherwise unchanged.
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      try {
        unawaited(_capture(
          error: error.toString(),
          stack: stack.toString(),
          kind: 'platform',
          fatal: true,
        ));
      } catch (_) {/* swallow — never re-throw from the top-level handler */}
      return previousPlatformOnError?.call(error, stack) ?? false;
    };
  }

  /// Sends any reports that were buffered while offline on a previous run.
  /// Best-effort; call once after the first frame.
  Future<void> flushPending() async {
    if (!EnvConfig.current.enableCrashReporting) return;
    try {
      final store = await _store;
      final raw = store.getString(_bufferKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List || decoded.isEmpty) return;

      final remaining = <dynamic>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final ok = await _send(Map<String, dynamic>.from(entry));
        if (!ok) remaining.add(entry); // keep unsent ones for the next launch
      }
      if (remaining.isEmpty) {
        await store.remove(_bufferKey);
      } else {
        await store.setString(_bufferKey, jsonEncode(remaining));
      }
    } catch (_) {/* best-effort */}
  }

  /// Manually report a caught error you still want visibility on (optional).
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String kind = 'manual',
    bool fatal = false,
  }) =>
      _capture(
        error: error.toString(),
        stack: stack?.toString(),
        kind: kind,
        fatal: fatal,
      );

  // ── internals ───────────────────────────────────────────────────────────────

  Future<void> _capture({
    required String error,
    String? stack,
    required String kind,
    required bool fatal,
  }) async {
    if (!EnvConfig.current.enableCrashReporting) return;
    if (_sentThisSession >= _maxPerSession) return;

    final cleanError = _redact(error, _maxErrorChars);
    final cleanStack = stack == null ? null : _redact(stack, _maxStackChars);

    // De-dupe: the first ~120 chars of the error is a stable-enough signature to
    // collapse a tight loop of the same crash into a single report per session.
    final signature =
        cleanError.length > 120 ? cleanError.substring(0, 120) : cleanError;
    if (!_seenSignatures.add(signature)) return;
    _sentThisSession += 1;

    final payload = <String, dynamic>{
      'error': cleanError,
      if (cleanStack != null) 'stack': cleanStack,
      'kind': kind,
      'severity': fatal ? 'fatal' : 'error',
      'appVersion': _appVersion,
      // platform/route are clamped to the server DTO's MaxLength(120) so an
      // unusually long OS string or deep route+query can never 422 the report.
      'platform': _clamp(_platformLabel(), 120),
      'route': _clampNullable(_currentRoute(), 120),
      'occurredAt': DateTime.now().millisecondsSinceEpoch,
    }..removeWhere((_, v) => v == null);

    final ok = await _send(payload);
    if (!ok) await _buffer(payload);
  }

  /// POSTs one report. Returns true on success. Never throws.
  Future<bool> _send(Map<String, dynamic> payload) async {
    try {
      final result = await DioApiService.instance.post<dynamic>(
        _endpoint,
        body: payload,
        requiresAuth: false, // a crash can happen pre-login (splash/auth)
      );
      return result.isOk;
    } catch (_) {
      return false;
    }
  }

  /// Appends [payload] to the bounded on-disk ring buffer (oldest dropped).
  Future<void> _buffer(Map<String, dynamic> payload) async {
    try {
      final store = await _store;
      final raw = store.getString(_bufferKey);
      final list = <dynamic>[];
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) list.addAll(decoded);
      }
      list.add(payload);
      while (list.length > _maxBuffered) {
        list.removeAt(0);
      }
      await store.setString(_bufferKey, jsonEncode(list));
    } catch (_) {/* best-effort */}
  }

  String _clamp(String value, int maxChars) =>
      value.length > maxChars ? value.substring(0, maxChars) : value;

  String? _clampNullable(String? value, int maxChars) =>
      value == null ? null : _clamp(value, maxChars);

  String? _currentRoute() {
    try {
      return routeResolver?.call();
    } catch (_) {
      return null;
    }
  }

  String _platformLabel() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Scrubs obvious secrets and bounds length before anything leaves the device.
  String _redact(String input, int maxChars) {
    var s = input;
    // Bearer tokens / JWT-ish blobs.
    s = s.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
      'Bearer [redacted]',
    );
    s = s.replaceAll(
      RegExp(r'eyJ[A-Za-z0-9._\-]{10,}'),
      '[redacted-token]',
    );
    // Long digit runs (phone/OTP/ids) → keep shape, drop value.
    s = s.replaceAll(RegExp(r'\b\d{6,}\b'), '[redacted-number]');
    // The truncation marker counts toward maxChars so the final string NEVER
    // exceeds the server DTO's MaxLength (else the report would 422 and be
    // retried from the offline buffer forever).
    const marker = '…[truncated]';
    if (s.length > maxChars) {
      s = s.substring(0, maxChars - marker.length) + marker;
    }
    return s;
  }
}

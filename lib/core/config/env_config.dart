import 'package:smart_meal_management/core/config/app_env.dart';

/// Environment-specific runtime configuration for the MealAttend platform.
///
/// All environment-sensitive values (base URL, timeouts, feature flags) live
/// here.  Feature code reads from [EnvConfig.current] — never hard-codes URLs.
///
/// Usage:
/// ```dart
/// final baseUrl = EnvConfig.current.apiBaseUrl;
/// final timeout = EnvConfig.current.connectTimeoutMs;
/// ```
class EnvConfig {
  const EnvConfig._({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
    required this.connectTimeoutMs,
    required this.receiveTimeoutMs,
    required this.sendTimeoutMs,
    required this.enableVerboseLogging,
    required this.enableAnalytics,
    required this.enableCrashReporting,
    required this.mockAuthEnabled,
  });

  // ── API ────────────────────────────────────────────────────────────────────

  /// Base URL for all REST API calls (no trailing slash).
  final String apiBaseUrl;

  /// Base URL for future WebSocket connections.
  /// Switches from ws:// (dev) to wss:// (prod) automatically.
  final String wsBaseUrl;

  // ── Timeouts (milliseconds) ────────────────────────────────────────────────

  final int connectTimeoutMs;
  final int receiveTimeoutMs;
  final int sendTimeoutMs;

  // ── Feature flags ──────────────────────────────────────────────────────────

  /// Log every HTTP request/response body. Always false in production.
  final bool enableVerboseLogging;

  /// Send analytics events (future Mixpanel / Amplitude integration).
  final bool enableAnalytics;

  /// Forward uncaught errors to crash reporter (future Sentry integration).
  final bool enableCrashReporting;

  /// When true, [AuthProvider] skips secure storage and loads a mock session.
  /// Automatically true in development; always false in production.
  final bool mockAuthEnabled;

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// Full versioned API prefix. e.g. `https://api.emilestone.com/v1`
  String get apiV1 => '$apiBaseUrl/v1';

  Duration get connectTimeout => Duration(milliseconds: connectTimeoutMs);
  Duration get receiveTimeout => Duration(milliseconds: receiveTimeoutMs);
  Duration get sendTimeout => Duration(milliseconds: sendTimeoutMs);

  // ── Environments ───────────────────────────────────────────────────────────

  // B10 LIVE MODE (2026-06-12):
  //   - apiBaseUrl 10.0.2.2 = host machine as seen from the Android emulator.
  //     Physical device: replace with your LAN IP (e.g. http://192.168.1.x:3000/api).
  //   - INSTANT ROLLBACK: set mockAuthEnabled back to true + hot restart
  //     → the entire app returns to in-memory mock mode (no other change needed).
  static const EnvConfig _development = EnvConfig._(
    apiBaseUrl: 'http://10.0.2.2:3000/api',
    wsBaseUrl: 'ws://10.0.2.2:3000',
    connectTimeoutMs: 10000,
    receiveTimeoutMs: 30000,
    sendTimeoutMs: 30000,
    enableVerboseLogging: true,
    enableAnalytics: false,
    enableCrashReporting: false,
    mockAuthEnabled: false, // B10: live backend (was true — flip back to roll back)
  );

  static const EnvConfig _staging = EnvConfig._(
    apiBaseUrl: 'https://staging-api.emilestone.com/api',
    wsBaseUrl: 'wss://staging-api.emilestone.com',
    connectTimeoutMs: 15000,
    receiveTimeoutMs: 30000,
    sendTimeoutMs: 30000,
    enableVerboseLogging: true,
    enableAnalytics: false,
    enableCrashReporting: true,
    mockAuthEnabled: false,
  );

  static const EnvConfig _production = EnvConfig._(
    apiBaseUrl: 'https://api.emilestone.com/api',
    wsBaseUrl: 'wss://api.emilestone.com',
    connectTimeoutMs: 15000,
    receiveTimeoutMs: 30000,
    sendTimeoutMs: 30000,
    enableVerboseLogging: false,
    enableAnalytics: true,
    enableCrashReporting: true,
    mockAuthEnabled: false,
  );

  // ── Active config resolver ─────────────────────────────────────────────────

  /// Returns the [EnvConfig] matching the active [AppEnv.current].
  static EnvConfig get current => switch (AppEnv.current) {
        AppEnvironment.development => _development,
        AppEnvironment.staging => _staging,
        AppEnvironment.production => _production,
      };
}

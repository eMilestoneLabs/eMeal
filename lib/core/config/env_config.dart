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
    required this.enableHttp2,
    required this.http2IdleTimeoutMs,
    required this.enableRequestDedup,
    required this.maxRequestRetries,
    required this.retryBaseDelayMs,
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

  /// Use the HTTP/2 transport for REST calls (multiplexes parallel requests
  /// over one TLS connection — big win on high-RTT links). Only effective over
  /// HTTPS; the client also auto-falls back to HTTP/1.1 per-connection if the
  /// server/proxy does not negotiate h2. Acts as a master kill-switch.
  final bool enableHttp2;

  /// How long an idle HTTP/2 connection is kept warm before being closed, in
  /// milliseconds. Keeping it warm across tab switches avoids a fresh TLS
  /// handshake on the next burst of calls. Only used when [enableHttp2] is on.
  final int http2IdleTimeoutMs;

  /// Coalesce concurrent identical GET requests into a single in-flight network
  /// call (request deduplication). Safe: only idempotent GETs are deduped, so
  /// the prefetch-then-navigate race never double-hits the backend.
  final bool enableRequestDedup;

  /// Max automatic retries for a **transient** GET failure (timeout / 5xx /
  /// connection error). 0 disables retry. Never applied to mutations or to
  /// validation/auth errors. Uses exponential backoff from [retryBaseDelayMs].
  final int maxRequestRetries;

  /// Base delay (ms) for the exponential backoff between GET retries
  /// (delay = base × 2^attempt). Configurable; never hardcoded.
  final int retryBaseDelayMs;

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// Full versioned API prefix. e.g. `https://api.emilestone.com/v1`
  String get apiV1 => '$apiBaseUrl/v1';

  Duration get connectTimeout => Duration(milliseconds: connectTimeoutMs);
  Duration get receiveTimeout => Duration(milliseconds: receiveTimeoutMs);
  Duration get sendTimeout => Duration(milliseconds: sendTimeoutMs);
  Duration get http2IdleTimeout => Duration(milliseconds: http2IdleTimeoutMs);

  /// HTTP/2 only works over TLS (h2 via ALPN), so it is enabled only when the
  /// master flag is on AND the base URL is HTTPS (never for local http dev).
  bool get useHttp2 => enableHttp2 && apiBaseUrl.startsWith('https://');

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
    enableHttp2: false, // dev is plain http:// — h2 (TLS/ALPN) not applicable
    http2IdleTimeoutMs: 60000,
    enableRequestDedup: true,
    maxRequestRetries: 2,
    retryBaseDelayMs: 300,
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
    enableHttp2: true, // https — multiplex parallel calls over one connection
    http2IdleTimeoutMs: 60000,
    enableRequestDedup: true,
    maxRequestRetries: 2,
    retryBaseDelayMs: 300,
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
    enableHttp2: true, // https — multiplex parallel calls over one connection
    http2IdleTimeoutMs: 60000,
    enableRequestDedup: true,
    maxRequestRetries: 2,
    retryBaseDelayMs: 300,
  );

  // ── Active config resolver ─────────────────────────────────────────────────

  /// Returns the [EnvConfig] matching the active [AppEnv.current].
  static EnvConfig get current => switch (AppEnv.current) {
        AppEnvironment.development => _development,
        AppEnvironment.staging => _staging,
        AppEnvironment.production => _production,
      };
}

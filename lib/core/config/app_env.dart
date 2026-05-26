/// Compile-time environment selector for the MealAttend platform.
///
/// Set via `--dart-define=ENV=production` (or staging) at build time.
/// Defaults to [AppEnvironment.development] when no dart-define is provided.
///
/// Usage:
/// ```dart
/// // Run in development (default):
/// flutter run
///
/// // Run in staging:
/// flutter run --dart-define=ENV=staging
///
/// // Build for production:
/// flutter build apk --dart-define=ENV=production
/// ```
///
/// Read the active environment anywhere in the app:
/// ```dart
/// if (AppEnv.isDevelopment) { ... }
/// final url = AppEnv.current == AppEnvironment.production
///     ? EnvConfig.production
///     : EnvConfig.development;
/// ```
enum AppEnvironment {
  development,
  staging,
  production;

  /// Human-readable display label for logging and debug UI.
  String get label => switch (this) {
        AppEnvironment.development => 'Development',
        AppEnvironment.staging => 'Staging',
        AppEnvironment.production => 'Production',
      };

  /// Short tag used in log prefixes: [DEV], [STG], [PROD].
  String get tag => switch (this) {
        AppEnvironment.development => 'DEV',
        AppEnvironment.staging => 'STG',
        AppEnvironment.production => 'PROD',
      };
}

/// Resolves the active [AppEnvironment] from the compile-time dart-define.
///
/// This class has no instance — use static accessors only.
abstract final class AppEnv {
  // Resolved once at startup from the dart-define string.
  // Falls back to development if the value is missing or unrecognised.
  static const String _envString = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );

  /// The active environment for this build.
  static final AppEnvironment current = _resolve(_envString);

  // ── Convenience shortcuts ──────────────────────────────────────────────────

  static bool get isDevelopment => current == AppEnvironment.development;
  static bool get isStaging => current == AppEnvironment.staging;
  static bool get isProduction => current == AppEnvironment.production;

  /// True in any non-production build — gates debug banners, verbose logging,
  /// inspector tools, and mock service overrides.
  static bool get isDebugBuild => !isProduction;

  // ── Internal ───────────────────────────────────────────────────────────────

  static AppEnvironment _resolve(String value) => switch (value.toLowerCase()) {
        'production' || 'prod' => AppEnvironment.production,
        'staging' || 'stg' => AppEnvironment.staging,
        _ => AppEnvironment.development,
      };
}

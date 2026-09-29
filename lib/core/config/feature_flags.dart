/// Build-time feature switches, set with `--dart-define=NAME=true`.
///
/// A switch only changes what users can reach. The feature's code, routes,
/// providers and server APIs stay intact, so turning it on needs no code
/// change.
abstract final class FeatureFlags {
  /// Events module (event admin + event guest).
  ///
  /// OFF (default): every Events route opens the "Events · Coming soon"
  /// preview instead (see `events_gate.dart`). ON: the full module as before.
  /// Enable with `--dart-define=EVENTS_ENABLED=true`.
  static const bool eventsEnabled = bool.fromEnvironment(
    'EVENTS_ENABLED',
    defaultValue: false,
  );
}

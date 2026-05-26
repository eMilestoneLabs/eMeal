import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/providers/theme_provider.dart';

/// State manager for admin settings.
///
/// Notifications and analytics toggles are persisted via [SharedPreferences].
/// Theme mode is delegated to the app-wide [ThemeProvider] so that toggling
/// the theme from admin settings affects the entire app — exactly the same
/// as the student settings screen does.
class AdminSettingsProvider extends ChangeNotifier {
  AdminSettingsProvider({
    required AuthProvider authProvider,
    required ThemeProvider themeProvider,
  })  : _authProvider = authProvider,
        _theme = themeProvider;

  final AuthProvider _authProvider;
  final ThemeProvider _theme;

  // ── SharedPreferences keys ─────────────────────────────────────────────────

  static const _kNotifications = 'admin_settings_notifications';
  static const _kAnalytics = 'admin_settings_analytics';

  // ── State ──────────────────────────────────────────────────────────────────

  bool _notificationsEnabled = true;
  bool _analyticsEnabled = true;
  bool _initialized = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get notificationsEnabled => _notificationsEnabled;
  bool get analyticsEnabled => _analyticsEnabled;

  /// Current app-wide [ThemeMode] — reads from the shared [ThemeProvider].
  ThemeMode get themeMode => _theme.themeMode;

  bool get isInitialized => _initialized;

  // ── Initialization ─────────────────────────────────────────────────────────

  /// Loads persisted toggle values from SharedPreferences.
  ///
  /// Call once from [AdminSettingsScreen.didChangeDependencies] before the
  /// first build.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _notificationsEnabled = prefs.getBool(_kNotifications) ?? true;
      _analyticsEnabled = prefs.getBool(_kAnalytics) ?? true;
    } catch (_) {
      // Fallback to defaults if SharedPreferences is unavailable.
    }
    _initialized = true;
    notifyListeners();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> setNotifications(bool value) async {
    if (_notificationsEnabled == value) return;
    _notificationsEnabled = value;
    notifyListeners();
    await _persist(_kNotifications, value);
  }

  Future<void> setAnalytics(bool value) async {
    if (_analyticsEnabled == value) return;
    _analyticsEnabled = value;
    notifyListeners();
    await _persist(_kAnalytics, value);
  }

  /// Delegates to [ThemeProvider.setThemeMode] — updates the entire app theme.
  Future<void> setThemeMode(ThemeMode mode) => _theme.setThemeMode(mode);

  Future<void> signOut() async {
    await _authProvider.logout();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _persist(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Silent fail — preference write errors are non-critical.
    }
  }
}

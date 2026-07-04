import 'package:flutter/material.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/providers/theme_provider.dart';

/// Manages the student settings toggles.
///
/// Delegates user-model mutations to [AuthProvider.refreshUser] so the
/// updated state is immediately visible everywhere (dashboard, profile, etc.)
class StudentSettingsProvider extends ChangeNotifier {
  StudentSettingsProvider({
    required AuthProvider authProvider,
    required ThemeProvider themeProvider,
  })  : _auth = authProvider,
        _theme = themeProvider {
    // Seed from persisted user preference so the toggle reflects what was saved.
    _remindersEnabled = authProvider.currentUser?.remindersEnabled ?? true;
    _auth.addListener(_onAuthChange);
  }

  final AuthProvider _auth;
  final ThemeProvider _theme;

  // ── Public getters ─────────────────────────────────────────────────────────

  UserModel? get _user => _auth.currentUser;

  bool get isVacationMode => _user?.isVacationMode ?? false;
  bool get isDefaultAttendance => _user?.isDefaultAttendance ?? false;
  // Pass 11 (FR-VACX-003): group context for the meal-granular vacation chips.
  String? get organizationId => _user?.organizationId;
  String? get activeGroupId {
    final ids = _user?.effectiveGroupIds ?? const <String>[];
    return ids.isNotEmpty ? ids.first : null;
  }
  bool get remindersEnabled => _remindersEnabled;
  ThemeMode get themeMode => _theme.themeMode;

  // Local-only — not persisted to backend in this MVP
  bool _remindersEnabled = true;

  // ── Mutators ───────────────────────────────────────────────────────────────

  /// Returns null on success, or the backend's human-readable failure message
  /// (e.g. approval-required / network) so the screen can show it — a silent
  /// snap-back toggle looked broken during live device tests.
  Future<String?> setVacationMode(bool value) async {
    final user = _user;
    if (user == null) return 'Not signed in';
    // Issue 4: persist to the backend (PATCH /users/me via updateProfile) so an
    // early turn-off actually sticks across reloads — this was previously an
    // in-memory-only refreshUser. updateProfile also updates the live session.
    final ok = await _auth.updateProfile(user.copyWith(isVacationMode: value));
    if (!ok) {
      return _auth.lastProfileError ??
          'Could not update vacation mode — please try again';
    }
    // Cancel all local notifications when vacation starts;
    // reminders will be rescheduled on next dashboard load when vacation ends.
    if (value) {
      NotificationService.instance.cancelAll();
    }
    // Note: rescheduling on vacation-off is handled by StudentDashboardProvider
    // on next load, so no action needed here.
    return null;
  }

  Future<void> setDefaultAttendance(bool value) async {
    final user = _user;
    if (user == null) return;
    await _auth.refreshUser(user.copyWith(isDefaultAttendance: value));
  }

  void setReminders(bool value) {
    if (_remindersEnabled == value) return;
    _remindersEnabled = value;
    // Cancel all scheduled reminders immediately when the user turns them off.
    // Re-scheduling happens the next time the dashboard loads (or vacation ends).
    if (!value) {
      NotificationService.instance.cancelAll();
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) => _theme.setThemeMode(mode);

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onAuthChange() {
    // Re-sync reminders preference whenever auth state changes (login, logout,
    // profile update) so the toggle always reflects the stored value.
    final userReminders = _user?.remindersEnabled;
    if (userReminders != null) {
      _remindersEnabled = userReminders;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChange);
    super.dispose();
  }
}

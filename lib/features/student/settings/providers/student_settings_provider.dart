import 'package:flutter/material.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
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

  // ── Per-group scope ────────────────────────────────────────────────────────
  //
  // Vacation and auto-attendance are PER GROUP: a member on leave in one group
  // must stay active in the others. The screen feeds this in from the shell's
  // GroupConfigScope (already loaded — no extra request), and every toggle
  // writes ONLY this group.
  String _scopedGroupId = '';
  MemberSettingOverrides? _overrides;
  // The shell's scope, so a successful write publishes the new value back to
  // the single source every screen reads. Without this the toggle would be
  // correct here but stale in the scope, and simply leaving and re-entering
  // Settings would bind the old value back over it.
  GroupConfigProvider? _scope;

  /// The group every write is scoped to.
  ///
  /// Normally the shell scope, but it falls back to the session's active group
  /// because Settings is reachable BEFORE the dashboard has loaded — a
  /// notification deep-links straight to `/student/settings`
  /// (notification_route_resolver). In that window the scope id is still empty,
  /// and without this fallback the toggle would silently take the ORG-WIDE
  /// path and change every group the member belongs to — the exact behaviour
  /// this feature removes. The session id is the same group: the server
  /// guarantees `groupId == groupIds[0]` and AuthProvider re-orders that list
  /// on a switch, so it always names the selected group.
  String get _effectiveScopeGroupId =>
      _scopedGroupId.isNotEmpty ? _scopedGroupId : (activeGroupId ?? '');

  /// The same group the toggles write to, for any OTHER control on this screen
  /// that targets a group (currently Request Vacation).
  ///
  /// They must agree. A group switch sets the session id first and the shell
  /// scope a moment later, so a control reading the session while the toggles
  /// read the scope can briefly aim at a DIFFERENT group than the one whose
  /// status the member is looking at. Resolving both here removes that window.
  /// Null when no group is known, matching the previous nullable contract.
  String? get scopedGroupIdOrNull =>
      _effectiveScopeGroupId.isEmpty ? null : _effectiveScopeGroupId;

  /// Point the toggles at the group the shell is currently showing.
  ///
  /// Deliberately does NOT notify: this is called from the screen's
  /// `didChangeDependencies`, and a `notifyListeners()` there reaches the
  /// screen's ListenableBuilder mid-dependency-phase — a `markNeedsBuild()`
  /// during build. The framework already rebuilds after
  /// `didChangeDependencies`, so the new scope is picked up on that very pass.
  /// Writes still notify (see [_writeSetting]), which is where the UI has to
  /// react without a rebuild being scheduled for it.
  void bindGroupScope(GroupConfigProvider scope) {
    _scope = scope;
    final groupId = scope.groupId;
    final overrides = scope.myMemberSettings;
    if (_scopedGroupId == groupId && _overrides == overrides) return;
    _scopedGroupId = groupId;
    _overrides = overrides;
  }

  // ── Public getters ─────────────────────────────────────────────────────────

  UserModel? get _user => _auth.currentUser;

  /// Vacation for THIS group, resolved exactly the way the server resolves it.
  ///
  /// Three inputs, in priority order:
  ///   1. an explicit per-group override always wins (`??`, never `||`);
  ///   2. otherwise the vacation's SCOPE decides. `isVacationMode` is the
  ///      ACCOUNT-level bit and now means exactly ORG-WIDE leave: a
  ///      group-scoped approved request is stored on the membership instead.
  ///      `vacationScopedGroupIds` still matters because a covering request
  ///      governs its group even BEFORE the membership is activated — the
  ///      same rule the server applies in getVacationCoveredUserIds, so the
  ///      toggle never disagrees with the server during activation lag;
  ///   3. null scope (pure toggle, ORG-LEVEL request, or an older server that
  ///      omits the field) means it governs every group — the previous
  ///      behaviour, unchanged.
  ///
  /// A covering request decides on its own, without consulting the flag:
  /// activation lag must never change what the member sees, which is the same
  /// reason the server ignores the flag once a request governs the date.
  bool get isVacationMode => MemberSettingOverrides.resolveVacationForGroup(
        override: _overrides?.isVacationMode,
        userFlag: _user?.isVacationMode ?? false,
        scopedGroupIds: _user?.vacationScopedGroupIds,
        groupId: _effectiveScopeGroupId,
      );
  bool get isDefaultAttendance => MemberSettingOverrides.resolve(
        _overrides?.isDefaultAttendance,
        _user?.isDefaultAttendance ?? false,
      );
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
    // Issue 4: persist to the backend so an early turn-off actually sticks
    // across reloads — this was previously an in-memory-only refreshUser.
    //
    // Scoped to THIS group when one is bound: Return Early then ends only this
    // group's covering vacation, instead of truncating a separately-approved
    // vacation in another group. With no group bound (or an older server) the
    // original org-wide profile write is used, unchanged.
    final error = await _writeSetting(
      value: value,
      scoped: () => _auth.setGroupVacationMode(
        groupId: _effectiveScopeGroupId,
        enabled: value,
      ),
      unscoped: () => _auth.updateProfile(user.copyWith(isVacationMode: value)),
      applyOverride: (v) => _overrides = MemberSettingOverrides(
        isVacationMode: v,
        isDefaultAttendance: _overrides?.isDefaultAttendance,
      ),
      fallbackMessage: 'Could not update vacation mode — please try again',
    );
    if (error != null) return error;
    // Cancel meal reminders when vacation starts (notepad reminders are
    // personal and unrelated to vacation); rescheduled on next dashboard
    // load when vacation ends.
    if (value) {
      NotificationService.instance.cancelMealReminders();
    }
    // Note: rescheduling on vacation-off is handled by StudentDashboardProvider
    // on next load, so no action needed here.
    return null;
  }

  /// Returns null on success, or the backend's failure message (same contract
  /// as [setVacationMode]). Live-Test-6 ISSUE-6: this was an in-memory-only
  /// refreshUser — the server value came back on every /auth/me refresh, so
  /// the toggle "randomly" re-enabled / refused to turn off. updateProfile
  /// persists it (PATCH /users/me — backend already accepts
  /// isDefaultAttendance) and updates the live session in one step.
  Future<String?> setDefaultAttendance(bool value) async {
    final user = _user;
    if (user == null) return 'Not signed in';
    // Scoped to THIS group when one is bound, so enabling auto-attendance here
    // cannot start auto-marking (and billing) the member in another group.
    return _writeSetting(
      value: value,
      scoped: () => _auth.setGroupDefaultAttendance(
        groupId: _effectiveScopeGroupId,
        enabled: value,
      ),
      unscoped: () =>
          _auth.updateProfile(user.copyWith(isDefaultAttendance: value)),
      applyOverride: (v) => _overrides = MemberSettingOverrides(
        isVacationMode: _overrides?.isVacationMode,
        isDefaultAttendance: v,
      ),
      fallbackMessage: 'Could not update auto-attendance — please try again',
    );
  }

  /// Shared write path for both toggles: pick the group-scoped endpoint when a
  /// group is bound, else the original profile write. Returns null on success
  /// or the backend's human-readable reason, so the screen can surface it
  /// instead of silently snapping the switch back.
  Future<String?> _writeSetting({
    required bool value,
    required Future<bool> Function() scoped,
    required Future<bool> Function() unscoped,
    required void Function(bool?) applyOverride,
    required String fallbackMessage,
  }) async {
    final useGroupScope = _effectiveScopeGroupId.isNotEmpty;
    final ok = await (useGroupScope ? scoped() : unscoped());
    if (!ok) return _auth.lastProfileError ?? fallbackMessage;
    if (useGroupScope) {
      // The server is the authority; record the now-explicit per-group value so
      // the switch reflects THIS group immediately, without a refetch...
      applyOverride(value);
      // ...and publish it to the shell scope, which is what every screen reads
      // and what this provider re-binds from. Skipping this leaves the scope
      // holding the pre-toggle value, so navigating away and back would bind
      // the old setting straight back over the new one.
      _scope?.setMemberSettings(_overrides);
      notifyListeners();
    }
    return null;
  }

  void setReminders(bool value) {
    if (_remindersEnabled == value) return;
    _remindersEnabled = value;
    // Cancel scheduled meal reminders immediately when the user turns them off
    // (notepad reminders have their own per-note control). Re-scheduling
    // happens the next time the dashboard loads (or vacation ends).
    if (!value) {
      NotificationService.instance.cancelMealReminders();
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

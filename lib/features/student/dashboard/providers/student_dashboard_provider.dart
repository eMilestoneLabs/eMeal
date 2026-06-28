import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/widgets.dart' show BuildContext, InheritedNotifier;
import 'package:smart_meal_management/data/contracts/i_attendance_repository.dart';
import 'package:smart_meal_management/data/contracts/i_group_repository.dart';
import 'package:smart_meal_management/data/contracts/i_meal_repository.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/repositories/vacation_repository.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/data/services/realtime_service.dart';
import 'package:smart_meal_management/core/constants/realtime_events.dart';

/// Student dashboard state manager.
///
/// Loads today's meals, attendance, 30-day summary, group config, and 7-day
/// attendance history (for streak) in a single parallel [Future.wait].
///
/// After the group config is fetched it notifies [GroupConfigProvider] so that
/// [StudentShell] can update the bottom-nav tab set (meals / menu tabs hide
/// when disabled by admin).
class StudentDashboardProvider extends ChangeNotifier {
  StudentDashboardProvider({
    IAttendanceRepository? attendanceRepo,
    IMealRepository? mealRepo,
    IGroupRepository? groupRepo,
    GroupConfigProvider? groupConfigProvider,
    VacationRepository? vacationRepo,
  })  : _attendanceRepo = attendanceRepo ?? AttendanceRepository(),
        _mealRepo = mealRepo ?? MealRepository(),
        _groupRepo = groupRepo ?? GroupRepository(),
        _vacationRepo = vacationRepo ?? VacationRepository(),
        _groupConfigProvider = groupConfigProvider;

  final IAttendanceRepository _attendanceRepo;
  final IMealRepository _mealRepo;
  final IGroupRepository _groupRepo;
  final VacationRepository _vacationRepo;

  /// Optional reference to the shell-owned provider; updated after group load.
  final GroupConfigProvider? _groupConfigProvider;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;
  // Issue 2: a failed quick-action (mark/skip) must NOT blank the whole
  // dashboard — it surfaces here for a snackbar, separate from load _error.
  String? _actionError;

  List<MealModel> _todayMeals = [];
  List<AttendanceModel> _todayAttendance = [];
  List<AttendanceModel> _weekHistory = [];
  AttendanceSummary? _summary;
  int _streakDays = 0;

  /// The student's currently-active approved vacation (covers today), used to
  /// show the "Approved: dd Mon → dd Mon" range on the dashboard badge. Null
  /// when not on vacation. Additive — never affects attendance/meals.
  VacationRequestModel? _activeVacation;
  VacationRequestModel? get activeVacation => _activeVacation;
  bool _isVacationMode = false;
  bool _remindersEnabled = true;
  GroupMealConfig _groupConfig = const GroupMealConfig();
  String _groupName = '';

  // ── B10 realtime ───────────────────────────────────────────────────────────
  StreamSubscription<RealtimeMessage>? _rtSub;
  Timer? _rtDebounce;
  String? _rtGroupId;
  UserModel? _rtUser;

  /// Events that should trigger a silent dashboard reload (group-scoped).
  static const Set<String> _rtEvents = <String>{
    RealtimeEvents.attendanceMarked,
    RealtimeEvents.attendanceUpdated,
    RealtimeEvents.attendanceOverridden,
    RealtimeEvents.mealUpdated,
    RealtimeEvents.mealPublished,
    RealtimeEvents.schedulePublished,
    RealtimeEvents.dashboardSummaryUpdated,
  };

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get actionError => _actionError;
  List<MealModel> get todayMeals => _todayMeals;
  List<AttendanceModel> get todayAttendance => _todayAttendance;
  AttendanceSummary? get summary => _summary;
  int get streakDays => _streakDays;
  bool get isVacationMode => _isVacationMode;
  bool get remindersEnabled => _remindersEnabled;
  GroupMealConfig get groupConfig => _groupConfig;
  String get groupName => _groupName;

  // ── Config-driven feature flags ────────────────────────────────────────────

  /// True when admin has meals enabled for this group.
  bool get mealsEnabled => _groupConfig.mealsEnabled;

  /// True when admin has weekly menu enabled for this group.
  bool get weeklyMenuEnabled => _groupConfig.weeklyMenuEnabled;

  /// True when admin has meal preferences enabled for this group.
  bool get preferencesEnabled => _groupConfig.preferencesEnabled;

  /// The subset of [MealPreferenceOption]s the admin enabled.
  List<MealPreferenceOption> get enabledPreferences =>
      _groupConfig.enabledPreferences;

  // ── Derived ────────────────────────────────────────────────────────────────

  /// Meal IDs for which the student has already taken attendance action today
  /// (present / absent / skipped / onVacation — anything except pending).
  ///
  /// Passed to [NotificationService.syncReminders] so reminders are skipped for
  /// meals the student has already responded to.
  Set<String> get markedMealIds => _todayAttendance
      .where((r) => r.status != AttendanceStatus.pending)
      .map((r) => r.mealId)
      .toSet();

  /// The meal to feature in the "Open Now" hero (null when meals off).
  ///
  /// Issue 8: prioritise the *actionable* meal — an open window the student has
  /// not yet acted on — so an already-marked earlier slot (e.g. Breakfast) never
  /// hides a still-open later slot (e.g. Dinner). Falls back to any open meal,
  /// then to the next upcoming (not-yet-past) meal.
  MealModel? get currentOrNextMeal {
    // 1) Open window the student has not yet responded to.
    for (final meal in _todayMeals) {
      if (isWindowOpen(meal) && !markedMealIds.contains(meal.id)) return meal;
    }
    // 2) Any open window (already marked) — still "Open Now".
    for (final meal in _todayMeals) {
      if (isWindowOpen(meal)) return meal;
    }
    // 3) Next upcoming meal whose window has not passed.
    for (final meal in _todayMeals) {
      if (!isWindowPast(meal)) return meal;
    }
    return null;
  }

  /// Feature 3: ordered meals for the "Open Now" carousel.
  ///
  /// Priority order (spec): pending-and-open meals first (force attention),
  /// then already-marked open meals, and — if nothing is open — a single
  /// fallback to the next upcoming (not-yet-past) meal. Empty when meals are
  /// off or nothing qualifies. Purely derived; no extra fetches or rebuilds.
  List<MealModel> get openNowMeals {
    final pendingOpen = <MealModel>[];
    final markedOpen = <MealModel>[];
    for (final m in _todayMeals) {
      if (!isWindowOpen(m)) continue;
      if (markedMealIds.contains(m.id)) {
        markedOpen.add(m);
      } else {
        pendingOpen.add(m);
      }
    }
    final ordered = <MealModel>[...pendingOpen, ...markedOpen];
    if (ordered.isNotEmpty) return ordered;
    for (final m in _todayMeals) {
      if (!isWindowPast(m)) return [m];
    }
    return const [];
  }

  /// Index inside [openNowMeals] of the first OPEN meal the student has not
  /// acted on yet, or -1 when every open meal is already marked. The carousel
  /// parks on this index and pauses auto-scroll to force attention.
  int get firstPendingOpenIndex {
    final list = openNowMeals;
    for (var i = 0; i < list.length; i++) {
      if (isWindowOpen(list[i]) && !markedMealIds.contains(list[i].id)) {
        return i;
      }
    }
    return -1;
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Concurrency lock — separate from [_isLoading] (which only drives the
  /// full loading view) so a cache-first paint can clear [_isLoading] while
  /// still preventing a second concurrent load.
  bool _isFetching = false;
  bool _menuPrefetched = false; // one-shot weekly-menu cache-warm per session

  Future<void> load({required UserModel user}) async {
    if (_isFetching) return;
    _isFetching = true;
    _isLoading = true;
    _error = null;

    // Immediately reflect vacation mode and reminders preference from the
    // user model so the UI updates before the async fetch completes.
    _isVacationMode = user.isVacationMode;
    _remindersEnabled = user.remindersEnabled;
    notifyListeners();

    final orgId = user.organizationId;
    // Resolve the user's primary group. If neither groupId nor groupIds is
    // set the student has not joined a group yet — bail early and show empty.
    final groupId =
        user.groupId ?? (user.groupIds.isNotEmpty ? user.groupIds.first : null);
    if (groupId == null) {
      _isLoading = false;
      _isFetching = false;
      notifyListeners();
      return;
    }
    final userId = user.id;
    final today = DateTime.now();
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));
    final sevenDaysAgo = today.subtract(const Duration(days: 7));

    // Cache-first (stale-while-revalidate): paint the last-known dashboard
    // core (today's meals + attendance + streak) instantly from local
    // storage; the network fetch below then overwrites everything. Atomic +
    // best-effort — absent/corrupt cache changes nothing and the loading view
    // shows as before.
    final dashCacheKey = 'student_dashboard:$orgId:$groupId:$userId';
    if (_todayMeals.isEmpty) {
      final cached = await ResponseCacheService.instance
          .read(dashCacheKey, maxAge: const Duration(hours: 12));
      if (cached is Map) {
        try {
          final meals = (cached['meals'] as List)
              .whereType<Map<String, dynamic>>()
              .map(MealModel.fromJson)
              .toList();
          final att = (cached['todayAtt'] as List)
              .whereType<Map<String, dynamic>>()
              .map(AttendanceModel.fromJson)
              .toList();
          final hist = (cached['weekHist'] as List)
              .whereType<Map<String, dynamic>>()
              .map(AttendanceModel.fromJson)
              .toList();
          final gn = cached['groupName'];
          _todayMeals = meals..sort((a, b) => a.order.compareTo(b.order));
          _todayAttendance = att;
          _weekHistory = hist;
          _streakDays = _computeStreak(_weekHistory);
          if (gn is String) _groupName = gn;
        } catch (_) {/* ignore corrupt cache; fetch will populate */}
      }
    }
    // Only show the full loading view when there is nothing cached to show.
    _isLoading = _todayMeals.isEmpty;
    notifyListeners();

    // ── Five parallel requests ─────────────────────────────────────────────
    final results = await Future.wait([
      // 0 — today's meals
      _mealRepo.getTodayMeals(organizationId: orgId, groupId: groupId),
      // 1 — today's attendance
      _attendanceRepo.getTodayAttendance(
        userId: userId,
        groupId: groupId,
        organizationId: orgId,
      ),
      // 2 — 30-day summary
      _attendanceRepo.getAttendanceSummary(
        userId: userId,
        groupId: groupId,
        organizationId: orgId,
        from: thirtyDaysAgo,
        to: today,
      ),
      // 3 — group model (config + name)
      _groupRepo.getGroup(organizationId: orgId, groupId: groupId),
      // 4 — 7-day history (for streak computation)
      _attendanceRepo.getAttendanceHistory(
        userId: userId,
        groupId: groupId,
        organizationId: orgId,
        from: sevenDaysAgo,
        to: today,
        params: const PaginationParams(page: 1, limit: 50),
      ),
    ]);

    // ── Unpack results ─────────────────────────────────────────────────────

    // Meals
    if (results[0] case Ok(:final value)) {
      _todayMeals = (value as List<MealModel>)
        ..sort((a, b) => a.order.compareTo(b.order));
    }

    // Today attendance
    if (results[1] case Ok(:final value)) {
      _todayAttendance = value as List<AttendanceModel>;
    }

    // Summary
    if (results[2] case Ok(:final value)) {
      _summary = value as AttendanceSummary;
    }

    // Group config + name
    if (results[3] case Ok(:final value)) {
      final group = value as GroupModel;
      _groupConfig = group.mealConfig;
      _groupName = group.name;
      // Push config to shell so nav tabs update immediately.
      _groupConfigProvider?.update(
        config: _groupConfig,
        groupName: _groupName,
      );
    }

    // 7-day history for streak
    if (results[4] case Ok(:final value)) {
      final paged = value as PaginatedResponse<AttendanceModel>;
      _weekHistory = paged.data;
    }

    // Streak from week history
    _streakDays = _computeStreak(_weekHistory);

    // Additive: when on vacation, resolve the active approved request so the
    // dashboard badge can show its "Approved: dd Mon → dd Mon" range. Members
    // only ever receive their own requests (backend-scoped). Never blocks load.
    _activeVacation = null;
    if (_isVacationMode) {
      final vres = await _vacationRepo.list(status: 'approved', limit: 50);
      if (vres case Ok(:final value)) {
        final now = DateTime.now();
        final todayOnly = DateTime(now.year, now.month, now.day);
        for (final v in value.data) {
          if (!v.startDate.isAfter(todayOnly) &&
              !v.endDate.isBefore(todayOnly)) {
            _activeVacation = v;
            break;
          }
        }
        _activeVacation ??=
            value.data.isNotEmpty ? value.data.first : null;
      }
    }

    // Sync local reminders (skip during vacation mode, skip already-marked meals)
    if (_remindersEnabled && !_isVacationMode && _todayMeals.isNotEmpty) {
      NotificationService.instance.syncReminders(
        _todayMeals,
        isVacationMode: _isVacationMode,
        markedMealIds: markedMealIds,
      );
    }

    // B10: subscribe to live updates for this group (no-op in mock mode).
    _bindRealtime(user, groupId);

    // Persist the dashboard core for instant cache-first paint next session.
    // Fire-and-forget; only real data (mirrors the no-empty rule).
    if (_todayMeals.isNotEmpty) {
      ResponseCacheService.instance.write(dashCacheKey, {
        'meals': _todayMeals.map((m) => m.toJson()).toList(),
        'todayAtt': _todayAttendance.map((a) => a.toJson()).toList(),
        'weekHist': _weekHistory.map((a) => a.toJson()).toList(),
        'groupName': _groupName,
      });
    }

    _isLoading = false;
    _isFetching = false;
    notifyListeners();

    // Prefetch the weekly menu once per session so the Menu tab is instant on
    // its FIRST open (cache-first only covers 2nd+ visits). Fire-and-forget.
    if (!_menuPrefetched) {
      _menuPrefetched = true;
      unawaited(_prefetchWeeklyMenu(orgId, groupId));
    }
  }

  /// Background cache-warm for the weekly menu. Best-effort; never affects the
  /// dashboard. Writes the same key the Menu provider reads.
  Future<void> _prefetchWeeklyMenu(String orgId, String groupId) async {
    try {
      final res = await _mealRepo.getCurrentWeekSchedule(
        organizationId: orgId,
        groupId: groupId,
      );
      if (res case Ok(:final value)) {
        if (value.id.isNotEmpty) {
          ResponseCacheService.instance
              .write('weekly_menu:$orgId:$groupId', value.toJson());
        }
      }
    } catch (_) {/* best-effort prefetch */}
  }

  // ── Sync attendance (called from StudentAttendanceProvider) ───────────────

  void syncAttendance(List<AttendanceModel> records) {
    _todayAttendance = records;
    notifyListeners();
  }

  /// Marks attendance for [meal] directly from the dashboard with an optimistic
  /// update + rollback, then keeps [_todayAttendance] in sync so the Next-Meal
  /// card flips to the Present badge immediately (Issue #1). Returns true on
  /// success. [user] supplies the ids; [_activeGroup] resolution mirrors [load].
  Future<bool> markStatus({
    required UserModel user,
    required MealModel meal,
    required AttendanceStatus status,
    String? preference,
  }) async {
    final groupId =
        user.groupId ?? (user.groupIds.isNotEmpty ? user.groupIds.first : null);
    if (groupId == null) return false;

    final today = DateTime.now();
    final existingIdx = _todayAttendance.indexWhere(
      (r) =>
          r.mealId == meal.id &&
          r.date.year == today.year &&
          r.date.month == today.month &&
          r.date.day == today.day,
    );

    final optimistic = existingIdx != -1
        ? _todayAttendance[existingIdx]
            .copyWith(status: status, preference: preference, markedAt: today)
        : AttendanceModel(
            id: 'temp_${meal.id}_${today.millisecondsSinceEpoch}',
            mealId: meal.id,
            userId: user.id,
            groupId: groupId,
            organizationId: user.organizationId,
            status: status,
            date: today,
            markedAt: today,
            preference: preference,
          );

    final snapshot = List<AttendanceModel>.from(_todayAttendance);
    if (existingIdx != -1) {
      _todayAttendance[existingIdx] = optimistic;
    } else {
      _todayAttendance = [..._todayAttendance, optimistic];
    }
    notifyListeners();

    final result = await _attendanceRepo.markAttendance(record: optimistic);
    switch (result) {
      case Ok(:final value):
        final idx = _todayAttendance.indexWhere((r) => r.id == optimistic.id);
        if (idx != -1) _todayAttendance[idx] = value;
        // Reminders no longer needed for a meal that's now marked.
        if (_remindersEnabled && !_isVacationMode && _todayMeals.isNotEmpty) {
          NotificationService.instance.syncReminders(
            _todayMeals,
            isVacationMode: _isVacationMode,
            markedMealIds: markedMealIds,
          );
        }
        notifyListeners();
        return true;
      case Err(:final failure):
        _todayAttendance = snapshot;
        // Issue 2: surface as an action error (snackbar) — do NOT set _error,
        // which would replace the whole dashboard with the error screen.
        _actionError = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  void setRemindersEnabled(bool enabled) {
    if (_remindersEnabled == enabled) return;
    _remindersEnabled = enabled;
    if (!enabled) {
      NotificationService.instance.cancelAll();
    } else if (!_isVacationMode && _todayMeals.isNotEmpty) {
      NotificationService.instance.syncReminders(
        _todayMeals,
        isVacationMode: _isVacationMode,
        markedMealIds: markedMealIds,
      );
    }
    notifyListeners();
  }

  void setVacationMode(bool enabled) {
    if (_isVacationMode == enabled) return;
    _isVacationMode = enabled;
    notifyListeners();
  }

  // ── Time helpers ──────────────────────────────────────────────────────────

  bool isWindowOpen(MealModel meal) {
    final now = TimeOfDay.now();
    final open = _parseTime(meal.attendanceWindow.openTime);
    final close = _parseTime(meal.attendanceWindow.closeTime);
    final nowMinutes = now.hour * 60 + now.minute;
    final openMinutes = open.hour * 60 + open.minute;
    final closeMinutes = close.hour * 60 + close.minute;
    return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
  }

  bool isWindowPast(MealModel meal) {
    final now = TimeOfDay.now();
    final close = _parseTime(meal.attendanceWindow.closeTime);
    final nowMinutes = now.hour * 60 + now.minute;
    final closeMinutes = close.hour * 60 + close.minute;
    return nowMinutes > closeMinutes;
  }

  AttendanceStatus? statusForMeal(String mealId) {
    final today = DateTime.now();
    try {
      return _todayAttendance
          .firstWhere(
            (a) =>
                a.mealId == mealId &&
                a.date.year == today.year &&
                a.date.month == today.month &&
                a.date.day == today.day,
          )
          .status;
    } catch (_) {
      return null;
    }
  }

  /// Issue 5: the ₹ price snapshotted onto today's attendance record for [mealId]
  /// (the price the student actually saw when they marked). Null when the meal
  /// is not yet marked or the record carries no price — callers then fall back
  /// to the live meal price. Prevents the displayed price drifting away from the
  /// billed price after an admin edits the meal config.
  int? snapshotPriceForMeal(String mealId) {
    final today = DateTime.now();
    try {
      return _todayAttendance
          .firstWhere(
            (a) =>
                a.mealId == mealId &&
                a.date.year == today.year &&
                a.date.month == today.month &&
                a.date.day == today.day,
          )
          .price;
    } catch (_) {
      return null;
    }
  }

  /// Today's attendance record for [mealId], or null when the student has not
  /// acted on it yet. Source of truth for the marked-state UI (status +
  /// preference + submitted time) so the screen always renders from backend
  /// attendance state rather than transient local UI flags.
  AttendanceModel? recordForMeal(String mealId) {
    final today = DateTime.now();
    try {
      return _todayAttendance.firstWhere(
        (a) =>
            a.mealId == mealId &&
            a.date.year == today.year &&
            a.date.month == today.month &&
            a.date.day == today.day,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  /// Computes the consecutive day streak from the most recent 7-day history.
  ///
  /// A day counts toward the streak only when every attendance record for  /// that day has [AttendanceStatus.present].
  int _computeStreak(List<AttendanceModel> history) {
    if (history.isEmpty) return 0;
    final now = DateTime.now();
    int streak = 0;
    for (int d = 0; d < 7; d++) {
      final day = DateTime(now.year, now.month, now.day - d);
      final dayRecords = history.where(
        (r) =>
            r.date.year == day.year &&
            r.date.month == day.month &&
            r.date.day == day.day,
      );
      if (dayRecords.isEmpty) break;
      final allPresent =
          dayRecords.every((r) => r.status == AttendanceStatus.present);
      if (!allPresent) break;
      streak++;
    }
    return streak;
  }

  // ── B10 realtime binding ───────────────────────────────────────────────────

  /// Joins the group room and subscribes to live events so the dashboard
  /// refreshes itself when attendance/meals change server-side. Idempotent
  /// and a no-op in mock mode (the socket is never opened).
  void _bindRealtime(UserModel user, String groupId) {
    _rtUser = user;
    if (_rtGroupId != groupId) {
      if (_rtGroupId != null) RealtimeService.instance.leaveGroup(_rtGroupId!);
      RealtimeService.instance.connect();
      RealtimeService.instance.joinGroup(groupId);
      _rtGroupId = groupId;
    }
    _rtSub ??= RealtimeService.instance.events
        .where((m) => _rtEvents.contains(m.name))
        .listen((_) => _scheduleRealtimeRefresh());
  }

  /// Coalesces bursts of events into a single reload.
  void _scheduleRealtimeRefresh() {
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 800), () {
      final user = _rtUser;
      if (user != null && !_isFetching) load(user: user);
    });
  }

  @override
  void dispose() {
    _rtDebounce?.cancel();
    _rtSub?.cancel();
    final g = _rtGroupId;
    if (g != null) RealtimeService.instance.leaveGroup(g);
    super.dispose();
  }
}

// ── StudentDashboardScope ──────────────────────────────────────────────────────

/// Provides a shell-level [StudentDashboardProvider] to the student subtree.
///
/// Created once in [StudentShell] so all student tabs (Home, Meals, etc.)
/// share a single provider instance — eliminates duplicate API calls when
/// switching tabs.
///
/// Usage:
/// ```dart
/// final provider = StudentDashboardScope.of(context);
/// ```
class StudentDashboardScope
    extends InheritedNotifier<StudentDashboardProvider> {
  const StudentDashboardScope({
    super.key,
    required StudentDashboardProvider notifier,
    required super.child,
  }) : super(notifier: notifier);

  static StudentDashboardProvider of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<StudentDashboardScope>();
    assert(scope != null, 'StudentDashboardScope not found in widget tree');
    return scope!.notifier!;
  }

  /// Returns null if there is no [StudentDashboardScope] in the tree.
  static StudentDashboardProvider? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<StudentDashboardScope>()
        ?.notifier;
  }

  @override
  bool updateShouldNotify(StudentDashboardScope oldWidget) => true;
}

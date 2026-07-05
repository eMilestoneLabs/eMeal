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
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
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
  // Pass 13 (FR-OFF-006): when the data on screen was produced — cache write
  // time while painting stale-while-revalidate data, "now" after a live load.
  DateTime? _lastUpdated;
  // Pass 13 (FR-OFF-012): set when SOME of the parallel loads failed — the
  // screen keeps rendering whatever loaded and shows a scoped retry banner.
  String? _sectionError;
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
  // #2: the member's per-group display role label (e.g. "Student" / "Member").
  // Empty when the membership has no explicit role (legacy joins).
  String _functionalRole = '';

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
    // SRS FR-MODE-012: mode flip mid-session → refresh so meal widgets
    // disappear/appear cleanly without stale actions.
    RealtimeEvents.groupConfigUpdated,
    // Module 22 (FR-HG-063, Pass 9): guest booked/cancelled/approved etc. —
    // host counters and billing preview change, refresh silently.
    RealtimeEvents.mealGuestUpdated,
  };

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  // FR-OFF-006: consumed by the FreshnessBadge on the dashboard header.
  DateTime? get lastUpdated => _lastUpdated;
  // FR-OFF-012: scoped partial-failure banner (null = all sections loaded).
  String? get sectionError => _sectionError;
  String? get actionError => _actionError;
  List<MealModel> get todayMeals => _todayMeals;
  List<AttendanceModel> get todayAttendance => _todayAttendance;
  AttendanceSummary? get summary => _summary;
  int get streakDays => _streakDays;
  bool get isVacationMode => _isVacationMode;
  bool get remindersEnabled => _remindersEnabled;
  GroupMealConfig get groupConfig => _groupConfig;
  String get groupName => _groupName;
  /// #2: the member's per-group display role label ('' when unset).
  String get functionalRole => _functionalRole;

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

  Future<void> load({
    required UserModel user,
    // SRS FR-MEMX-009 (Pass 10): when the active group turns out to be
    // archived/revoked, [load] retries itself once per remaining membership
    // instead of leaving a broken screen. Internal — call sites never set it.
    String? overrideGroupId,
    Set<String>? triedGroupIds,
  }) async {
    if (_isFetching && overrideGroupId == null) return;
    _isFetching = true;
    _isLoading = true;
    _error = null;
    _sectionError = null;

    // Immediately reflect vacation mode and reminders preference from the
    // user model so the UI updates before the async fetch completes.
    _isVacationMode = user.isVacationMode;
    _remindersEnabled = user.remindersEnabled;
    notifyListeners();

    final orgId = user.organizationId;
    // Resolve the user's primary group. If neither groupId nor groupIds is
    // set the student has not joined a group yet — bail early and show empty.
    final groupId = overrideGroupId ??
        user.groupId ??
        (user.groupIds.isNotEmpty ? user.groupIds.first : null);
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
        // Pass 13 (FR-OFF-006): remember how old the painted cache is so the
        // UI can show a freshness badge until the live refresh lands.
        ResponseCacheService.instance
            .readTimestamp(dashCacheKey)
            .then((ts) {
          if (ts != null && _lastUpdated == null) {
            _lastUpdated = ts;
            notifyListeners();
          }
        });
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
          final fr = cached['functionalRole'];
          _todayMeals = meals..sort(MealModel.compareChronological);
          _todayAttendance = att;
          _weekHistory = hist;
          _streakDays = _computeStreak(_weekHistory);
          if (gn is String) _groupName = gn;
          if (fr is String) _functionalRole = fr; // #2: role from cache
          // Cold-start zeros fix: restore the 30-day summary so the KPI cards
          // (attendance %, present/absent counts) paint last-known values
          // instead of 0 while the network refresh runs.
          final sm = cached['summary'];
          if (sm is Map) {
            _summary = AttendanceSummary.fromJson(sm.cast<String, dynamic>());
          }
          // Restore the group meal-config so mode-driven widgets/tabs render
          // in their last-known mode instead of defaults, then snapping.
          final gc = cached['groupConfig'];
          if (gc is Map) {
            _groupConfig = GroupMealConfig.fromJson(gc.cast<String, dynamic>());
            _groupConfigProvider?.update(
              config: _groupConfig,
              groupName: _groupName,
            );
          }
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

    // Pass 13 (FR-OFF-012): partial-failure accounting. Whatever loaded is
    // rendered; failures are counted so the screen can show a full error only
    // when NOTHING loaded, or a scoped retry banner when SOME sections failed.
    var failedSections = 0;
    String? firstFailureMessage;
    for (final r in results) {
      if (r case Err(:final failure)) {
        failedSections++;
        firstFailureMessage ??= failure.message;
      }
    }

    // Meals
    if (results[0] case Ok(:final value)) {
      _todayMeals = (value as List<MealModel>)
        ..sort(MealModel.compareChronological);
      // Server-clock window gating baseline — LIVE payloads only (cached
      // paints never carry orgClockMinutes, so this stamp is inert for them).
      _mealsFetchedAt = DateTime.now();
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
    var groupUnavailable = false;
    if (results[3] case Ok(:final value)) {
      final group = value as GroupModel;
      // SRS FR-MEMX-009: an archived active group must never render as a
      // working dashboard — treat it like a failed group fetch below.
      if (group.isActive == false) {
        groupUnavailable = true;
      } else {
        _groupConfig = group.mealConfig;
        _groupName = group.name;
        // #2: the requester's per-group display role (backend computes this
        // from their GroupMember.functionalRole). Empty = fall back to nothing.
        _functionalRole = group.functionalRole?.label ?? '';
        // Push config to shell so nav tabs update immediately.
        _groupConfigProvider?.update(
          config: _groupConfig,
          groupName: _groupName,
        );
      }
    } else if (results[3] case Err()) {
      // 403 GROUP_ARCHIVED / revoked access / 404 all land here.
      groupUnavailable = true;
    }

    // SRS FR-MEMX-009 (Pass 10): safe fallback — pick the next membership
    // the user still holds and reload once for it; with no alternative left,
    // fall through and let the existing empty/error states render (never a
    // half-broken screen with stale group data).
    if (groupUnavailable) {
      final tried = {...(triedGroupIds ?? const <String>{}), groupId};
      final alternatives =
          user.groupIds.where((g) => !tried.contains(g)).toList();
      if (alternatives.isNotEmpty) {
        _isFetching = false;
        return load(
          user: user,
          overrideGroupId: alternatives.first,
          triedGroupIds: tried,
        );
      }
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
        'functionalRole': _functionalRole, // #2: persist per-group role
        // Cold-start zeros fix: persist the KPI summary + meal-config so the
        // next cache-first paint restores them (never 0 / default mode).
        if (_summary != null) 'summary': _summary!.toJson(),
        'groupConfig': _groupConfig.toJson(),
      });
    }

    // Pass 13 (ES-001 / FR-OFF-012): classify the outcome. Everything failed
    // with nothing to show → full error state (retry re-runs this load with
    // the same group). Partial failure → keep the screen, flag the gap.
    if (failedSections == results.length &&
        _todayMeals.isEmpty &&
        _summary == null) {
      _error = firstFailureMessage ?? 'Could not load your dashboard.';
    } else if (failedSections > 0) {
      _sectionError =
          'Some sections could not refresh — showing last known data.';
    }

    // Pass 13 (FR-OFF-006): only stamp freshness when live data landed.
    if (failedSections < results.length) {
      _lastUpdated = DateTime.now();
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
    // Module 36 (FR-PG-031): multi-group selection set for Present marks on
    // meals with explicit preference groups; null = legacy flat path.
    List<PreferenceSelection>? selections,
  }) async {
    final groupId =
        user.groupId ?? (user.groupIds.isNotEmpty ? user.groupIds.first : null);
    if (groupId == null) return false;

    final now = DateTime.now();
    // Mark with the SERVER's org-timezone business date when known (rides on
    // live /meals/today payloads) — a wrong phone calendar date used to 400
    // with "Attendance can only be marked for today".
    final today = _parseOrgDate(meal.orgDate) ?? now;
    // Match by mealId within today's already-scoped list — NO device-date
    // comparison. The read side (recordForMeal) does the same, so an optimistic
    // mark and its server echo can never split into two records across a
    // timezone / phone-clock / near-midnight boundary (root cause of the mark
    // reverting to "Mark Attendance").
    final existingIdx =
        _todayAttendance.indexWhere((r) => r.mealId == meal.id);

    final optimistic = existingIdx != -1
        ? _todayAttendance[existingIdx].copyWith(
            status: status,
            preference: preference,
            markedAt: now,
            selections: selections)
        : AttendanceModel(
            id: 'temp_${meal.id}_${now.millisecondsSinceEpoch}',
            mealId: meal.id,
            userId: user.id,
            groupId: groupId,
            organizationId: user.organizationId,
            status: status,
            date: today,
            markedAt: now,
            preference: preference,
            selections: selections,
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
  //
  // GOLDEN FIX (live-device "sometimes can't mark Present"): window gating
  // previously trusted the PHONE clock while the server enforces the ORG-
  // timezone server clock with close-EXCLUSIVE + grace semantics
  // (FR-TIME-002/005/008). A skewed/wrong-timezone device enabled buttons the
  // server 423'd — or disabled marking the server would accept (grace!).
  // Live /meals/today payloads now carry the server's org clock
  // ([MealModel.orgClockMinutes] + [graceMinutes], captured at fetch); gating
  // advances that clock by device-side ELAPSED time (immune to the absolute
  // wall clock being wrong) and mirrors the server's exact semantics.
  // Cached payloads never carry the fields → legacy phone-clock fallback,
  // replaced within ~1s by the SWR silent refresh.

  /// Device timestamp of the most recent LIVE /meals/today payload — the
  /// baseline that [_orgNowMinutes] advances from.
  DateTime? _mealsFetchedAt;

  /// "YYYY-MM-DD" → local-midnight DateTime for that calendar date; null on
  /// missing/unparsable input (callers fall back to the device date).
  static DateTime? _parseOrgDate(String? s) {
    if (s == null || s.length < 10) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    final d = int.tryParse(s.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// Server org-clock "now" (minutes since org midnight), advanced by elapsed
  /// device time since fetch. Null → caller falls back to the phone clock.
  int? _orgNowMinutes(MealModel meal) {
    final base = meal.orgClockMinutes;
    final at = _mealsFetchedAt;
    if (base == null || at == null) return null;
    final elapsed = DateTime.now().difference(at).inMinutes;
    // Monotonicity guard: clock jumped backwards or payload is ancient
    // (screen resumed after >12h) — fall back rather than extrapolate.
    if (elapsed < 0 || elapsed > 12 * 60) return null;
    return (base + elapsed) % (24 * 60);
  }

  static int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// True while the server accepts a mark for [meal]: open ≤ now < close+grace
  /// (grace marks are accepted server-side — FR-TIME-005). The all-day
  /// 00:00–23:59 window (client shape of "no window") is always open.
  bool isWindowOpen(MealModel meal) {
    final w = meal.attendanceWindow;
    if (w.openTime == '00:00' && w.closeTime == '23:59') return true;
    final openMinutes = _minutesOf(_parseTime(w.openTime));
    final closeMinutes = _minutesOf(_parseTime(w.closeTime));
    final orgNow = _orgNowMinutes(meal);
    if (orgNow != null) {
      final grace = meal.graceMinutes ?? 0;
      return orgNow >= openMinutes && orgNow < closeMinutes + grace;
    }
    // Legacy fallback (cached payloads / pre-fix servers): phone clock.
    final nowMinutes = _minutesOf(TimeOfDay.now());
    return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
  }

  bool isWindowPast(MealModel meal) {
    final w = meal.attendanceWindow;
    if (w.openTime == '00:00' && w.closeTime == '23:59') return false;
    final closeMinutes = _minutesOf(_parseTime(w.closeTime));
    final orgNow = _orgNowMinutes(meal);
    if (orgNow != null) {
      final grace = meal.graceMinutes ?? 0;
      return orgNow >= closeMinutes + grace;
    }
    final nowMinutes = _minutesOf(TimeOfDay.now());
    return nowMinutes > closeMinutes;
  }

  AttendanceStatus? statusForMeal(String mealId) =>
      recordForMeal(mealId)?.status;

  /// Issue 5: the ₹ price snapshotted onto today's attendance record for [mealId]
  /// (the price the student actually saw when they marked). Null when the meal
  /// is not yet marked or the record carries no price — callers then fall back
  /// to the live meal price. Prevents the displayed price drifting away from the
  /// billed price after an admin edits the meal config.
  int? snapshotPriceForMeal(String mealId) => recordForMeal(mealId)?.price;

  /// Today's attendance record for [mealId], or null when the student has not
  /// acted on it yet. Source of truth for the marked-state UI (status +
  /// preference + submitted time) so the screen always renders from backend
  /// attendance state rather than transient local UI flags.
  AttendanceModel? recordForMeal(String mealId) {
    // Single source of truth for the marked-state UI. Keyed by mealId ONLY:
    // [_todayAttendance] is already scoped to today by load(), and both the
    // optimistic write and the reloaded server record store the org-timezone
    // business date — so a device-date filter here (the old code) dropped the
    // record whenever the phone date differed from the org date, reverting the
    // card to "Mark Attendance". Matching by mealId removes that failure mode.
    for (final a in _todayAttendance) {
      if (a.mealId == mealId) return a;
    }
    return null;
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

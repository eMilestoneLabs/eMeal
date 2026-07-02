import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, InheritedNotifier;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/dashboard_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_attendance_summary.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/data/services/realtime_service.dart';
import 'package:smart_meal_management/core/constants/realtime_events.dart';

/// Repository-driven provider for the admin home dashboard.
///
/// Fetches groups via [GroupRepository], today's meals via [MealRepository],
/// and today's attendance stats via [AttendanceRepository]. Exposes headline
/// KPIs (total members, groups, present today, absent today, attendance rate),
/// the group list, and the active meal list for window-close alerts.
class AdminDashboardProvider extends ChangeNotifier {
  AdminDashboardProvider({
    GroupRepository? groupRepository,
    AttendanceRepository? attendanceRepository,
    MealRepository? mealRepository,
    DashboardRepository? dashboardRepository,
  })  : _groupRepo = groupRepository ?? GroupRepository(),
        _attendanceRepo = attendanceRepository ?? AttendanceRepository(),
        _mealRepo = mealRepository ?? MealRepository(),
        _dashboardRepo = dashboardRepository ?? DashboardRepository();

  final GroupRepository _groupRepo;
  final AttendanceRepository _attendanceRepo;
  final MealRepository _mealRepo;
  final DashboardRepository _dashboardRepo;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool _isFetching = false; // concurrency lock (separate from spinner)
  String? _error;
  List<GroupModel> _groups = [];
  List<MealModel> _todayMeals = [];
  int _presentToday = 0;
  int _absentToday = 0;
  int _todayTotal = 0;
  String _adminName = 'Admin';
  String _orgName = 'Your Organisation';

  // ── Per-group counts (Issue #5) ─────────────────────────────────────────────
  // Keyed by groupId so the dashboard can show stats for one selected group.
  final Map<String, int> _presentByGroup = {};
  final Map<String, int> _absentByGroup = {};
  final Map<String, int> _totalByGroup = {};

  // ── Meal-wise summaries (Issue 1 + Issue 5) ─────────────────────────────────
  // mealId -> per-meal present/absent/skipped + preference breakdown, fetched
  // from the existing GET /attendance/meal-summary endpoint.
  final Map<String, MealAttendanceSummary> _mealSummaries = {};

  /// The group whose stats are shown. Null = "All groups" (aggregate).
  /// Acts as the admin's default group (Issue #8); persisted client-side.
  String? _selectedGroupId;

  /// Last 5 attendance records across all groups — used for the activity feed.
  List<AttendanceModel> _recentActivity = [];

  // ── B10 realtime ───────────────────────────────────────────────────────────
  StreamSubscription<RealtimeMessage>? _rtSub;
  Timer? _rtDebounce;
  final Set<String> _rtJoinedGroups = <String>{};
  String? _rtAdminId;
  String? _rtOrgId;
  String _rtName = 'Admin';
  String _rtOrgName = 'Your Organisation';

  /// Org/admin-room + group-scoped events that trigger a silent reload.
  static const Set<String> _rtEvents = <String>{
    RealtimeEvents.attendanceMarked,
    RealtimeEvents.attendanceUpdated,
    RealtimeEvents.attendanceOverridden,
    RealtimeEvents.attendanceAnalyticsUpdated,
    RealtimeEvents.analyticsUpdated,
    RealtimeEvents.dashboardSummaryUpdated,
    RealtimeEvents.dashboardUpdated,
    RealtimeEvents.mealUpdated,
    RealtimeEvents.mealPublished,
    RealtimeEvents.schedulePublished,
    RealtimeEvents.scheduleUpdated,
    RealtimeEvents.groupMemberUpdated,
    RealtimeEvents.memberBlocked,
  };

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<GroupModel> get groups => _groups;

  /// Active meals for today — used by the meal window alert card.
  List<MealModel> get todayMeals => _todayMeals;

  String get adminName => _adminName;
  String get orgName => _orgName;

  int get groupCount => _groups.length;

  /// The currently selected group (null when showing all groups).
  String? get selectedGroupId => _selectedGroupId;
  GroupModel? get selectedGroup {
    for (final g in _groups) {
      if (g.id == _selectedGroupId) return g;
    }
    return null;
  }

  /// Members for the selected group, or all groups combined when none selected.
  int get totalMembers => _selectedGroupId == null
      ? _groups.fold(0, (s, g) => s + g.memberCount)
      : (selectedGroup?.memberCount ?? 0);

  /// Present/absent/total respect the selected group (Issue #5).
  int get presentToday =>
      _selectedGroupId == null ? _presentToday : (_presentByGroup[_selectedGroupId] ?? 0);
  int get absentToday =>
      _selectedGroupId == null ? _absentToday : (_absentByGroup[_selectedGroupId] ?? 0);

  int get _selectedTotal =>
      _selectedGroupId == null ? _todayTotal : (_totalByGroup[_selectedGroupId] ?? 0);

  double get attendanceRate =>
      _selectedTotal == 0 ? 0.0 : presentToday / _selectedTotal;

  /// Today's active meals for the selected group, sorted by admin order.
  /// Powers the meal-wise attendance + preference breakdown (Issue 5).
  List<MealModel> get selectedGroupTodayMeals {
    final gid = _selectedGroupId;
    final list = _todayMeals
        .where((m) => gid == null || m.groupId == gid)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// Per-meal attendance + preference summary for [mealId] (null until loaded).
  MealAttendanceSummary? mealSummary(String mealId) => _mealSummaries[mealId];

  /// Recent activity, filtered to the selected group when one is chosen.
  List<AttendanceModel> get recentActivity => _selectedGroupId == null
      ? _recentActivity
      : _recentActivity.where((r) => r.groupId == _selectedGroupId).toList();

  /// Switch the active/default group and refresh derived stats. Persisted so it
  /// becomes the admin's default group across sessions (Issue #8).
  void selectGroup(String? groupId) {
    if (_selectedGroupId == groupId) return;
    _selectedGroupId = groupId;
    notifyListeners();
    _persistDefaultGroup(groupId);
  }

  // ── Default group persistence (Issue #8, client-side MVP) ───────────────────
  static const String _kDefaultGroupKey = 'admin_default_group_id';

  Future<void> _persistDefaultGroup(String? groupId) async {
    final prefs = await SharedPreferences.getInstance();
    if (groupId == null) {
      await prefs.remove(_kDefaultGroupKey);
    } else {
      await prefs.setString(_kDefaultGroupKey, groupId);
    }
  }

  Future<String?> _loadDefaultGroup() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDefaultGroupKey);
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  Future<void> load({
    required String adminId,
    required String organizationId,
    String name = 'Admin',
    /// Display name of the organisation. When the real backend is integrated,
    /// pass the org name returned by the API. Until then the field defaults to
    /// 'Your Organisation' — never derived from a group name.
    String organizationName = 'Your Organisation',
  }) async {
    if (_isFetching) return;
    _isFetching = true;
    _isLoading = true;
    _error = null;
    _adminName = name;
    _orgName = organizationName;
    _rtAdminId = adminId;
    _rtOrgId = organizationId;
    _rtName = name;
    _rtOrgName = organizationName;
    notifyListeners();

    // Cache-first (stale-while-revalidate): paint last-known KPIs + recent
    // activity instantly; the fetches below overwrite. Atomic + best-effort.
    final dashKey = 'admin_dashboard:$organizationId';
    if (_groups.isEmpty) {
      final cached = await ResponseCacheService.instance
          .read(dashKey, maxAge: const Duration(hours: 12));
      if (cached is Map) {
        try {
          final groups = (cached['groups'] as List)
              .whereType<Map<String, dynamic>>()
              .map(GroupModel.fromJson)
              .toList();
          final meals = (cached['meals'] as List)
              .whereType<Map<String, dynamic>>()
              .map(MealModel.fromJson)
              .toList();
          final activity = (cached['activity'] as List)
              .whereType<Map<String, dynamic>>()
              .map(AttendanceModel.fromJson)
              .toList();
          // All list parses succeeded — assign atomically (no partial state).
          _groups = groups;
          _todayMeals = meals;
          _recentActivity = activity;
          _presentToday = (cached['present'] as num?)?.toInt() ?? 0;
          _absentToday = (cached['absent'] as num?)?.toInt() ?? 0;
          _todayTotal = (cached['total'] as num?)?.toInt() ?? 0;
          _restoreIntMap(_presentByGroup, cached['presentByGroup']);
          _restoreIntMap(_absentByGroup, cached['absentByGroup']);
          _restoreIntMap(_totalByGroup, cached['totalByGroup']);
          final sg = cached['selectedGroupId'];
          if (sg is String) _selectedGroupId = sg;
        } catch (_) {/* ignore corrupt cache */}
      }
    }
    _isLoading = _groups.isEmpty;
    notifyListeners();

    // GOLDEN PATH — single round-trip: GET /dashboard/admin/overview returns
    // groups + today's meals + per-meal summaries + recent activity in ONE
    // response (the backend composes the exact same per-endpoint payloads), so
    // a cold dashboard costs 1 network round-trip instead of 3 sequential
    // waves (1 + 2N + M requests). On ANY failure — older backend without the
    // endpoint, network error, unexpected shape — we fall through to the
    // legacy wave-by-wave path below, unchanged. Deploy-order safe.
    if (await _tryLoadFromOverview(organizationName)) {
      if (_groups.isNotEmpty) {
        await _restoreDefaultGroupSelection();
      }
      _bindRealtime();
      if (_groups.isNotEmpty) {
        _writeDashCache(dashKey);
      }
      _isLoading = false;
      _isFetching = false;
      notifyListeners();
      return;
    }

    // 1. Fetch groups for this organisation
    final groupsResult = await _groupRepo.getOrganisationGroups(
      organizationId: organizationId,
    );

    switch (groupsResult) {
      case Ok(:final value):
        _groups = value.data;
        // Derive org display name from loaded groups when no explicit name
        // was passed (PHASE_B6: replace with real org name from API response).
        if (organizationName == 'Your Organisation' && _groups.isNotEmpty) {
          _orgName = _groups.length == 1
              ? _groups.first.name
              : '${_groups.length} Groups';
        }
      case Err(:final failure):
        _error = failure.message;
        _isLoading = false;
        _isFetching = false;
        notifyListeners();
        return;
    }

    // Kick off the recent-activity (history) fetch NOW. It only depends on the
    // group list — not on meals or summaries — so we start it here and await it
    // later, letting it run concurrently with steps 2 + 3a instead of waiting
    // for them to finish first (removes one sequential round-trip). Additive:
    // same call, same params, only the await is deferred.
    final today = _today();
    final now = DateTime.now();
    Future<List<Result<PaginatedResponse<AttendanceModel>>>>? historyResultsFuture;
    if (_groups.isNotEmpty) {
      historyResultsFuture = Future.wait(
        _groups.map(
          (g) => _attendanceRepo.getAttendanceHistory(
            userId: '',
            groupId: g.id,
            organizationId: organizationId,
            from: today,
            to: now,
            params: const PaginationParams(page: 1, limit: 5),
          ),
        ),
      );
    }

    // 2. Fetch today's meals across ALL groups in parallel (used for window
    //    alerts). Each group may have its own meal schedule so we union them.
    if (_groups.isNotEmpty) {
      final mealFutures = _groups.map(
        (g) => _mealRepo.getTodayMeals(
          organizationId: organizationId,
          groupId: g.id,
        ),
      );
      final mealResults = await Future.wait(mealFutures);
      final seenIds = <String>{};
      final merged = <MealModel>[];
      for (final result in mealResults) {
        if (result case Ok(:final value)) {
          for (final meal in value) {
            if (seenIds.add(meal.id)) merged.add(meal);
          }
        }
      }
      _todayMeals = merged;
    }

    // 3. Fetch today's attendance summary across ALL groups in parallel and
    //    aggregate the counts — admins with 10+ groups get correct totals.
    if (_groups.isNotEmpty) {
      // 3a. Meal-wise attendance summaries — reuse GET /attendance/meal-summary
      // for each active meal today. Fixes Issue 1 (the group /attendance/summary
      // endpoint resolved userId to the admin's OWN id -> always 0) and powers
      // meal-wise present/absent + preference breakdown (Issue 5).
      _mealSummaries.clear();
      final mealSummaryFutures = _todayMeals
          .map((m) => _attendanceRepo.getMealAttendanceSummary(
                organizationId: organizationId,
                mealId: m.id,
                date: today,
              ))
          .toList();
      final mealSummaryResults = await Future.wait(mealSummaryFutures);
      for (var i = 0; i < _todayMeals.length; i++) {
        if (mealSummaryResults[i] case Ok(:final value)) {
          _mealSummaries[_todayMeals[i].id] = value;
        }
      }

      // Derive per-group present/absent/total by summing meal-wise counts.
      _deriveCountsFromSummaries();

      // Issue #8: restore the saved default group, or default to the first one
      // so the dashboard opens on a concrete group rather than a vague total.
      await _restoreDefaultGroupSelection();

      // 3b. Recent activity feed — await the history fetch started above (it ran
      // concurrently with steps 2 + 3a), then merge, sort, cap at 5.
      final historyResults = await (historyResultsFuture ??
          Future.value(<Result<PaginatedResponse<AttendanceModel>>>[]));

      final allRecords = <AttendanceModel>[];
      for (final result in historyResults) {
        if (result case Ok(:final value)) {
          allRecords.addAll(
            value.data.where((r) => r.status != AttendanceStatus.pending),
          );
        }
      }
      // Sort descending by markedAt (falls back to date) and take the 5 most recent.
      allRecords.sort((a, b) =>
          (b.markedAt ?? b.date).compareTo(a.markedAt ?? a.date));
      _recentActivity = allRecords.take(5).toList();
    }

    // B10: join group rooms + subscribe to live events (no-op in mock mode).
    _bindRealtime();

    // Persist the dashboard KPI core for instant cache-first paint next time.
    if (_groups.isNotEmpty) {
      _writeDashCache(dashKey);
    }

    _isLoading = false;
    _isFetching = false;
    notifyListeners();
  }

  // ── Overview golden path (single round-trip) ────────────────────────────────

  /// Loads the whole dashboard from GET /dashboard/admin/overview (one call).
  ///
  /// Parses every section into locals FIRST and only then commits to provider
  /// state, so a malformed response can never leave partial state. Returns
  /// false on any failure so [load] falls back to the legacy wave path.
  Future<bool> _tryLoadFromOverview(String organizationName) async {
    final result = await _dashboardRepo.getAdminOverview(date: _today());
    switch (result) {
      case Err():
        return false;
      case Ok(:final value):
        try {
          final groupsJson = value['groups'];
          if (groupsJson is! Map) return false;
          final groups = PaginatedResponse.fromJson(
            groupsJson.cast<String, dynamic>(),
            GroupModel.fromJson,
          ).data;
          final meals = ((value['todayMeals'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(MealModel.fromJson)
              .toList();
          final summaries = <String, MealAttendanceSummary>{};
          for (final s in ((value['mealSummaries'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()) {
            final parsed = MealAttendanceSummary.fromJson(s);
            summaries[parsed.mealId] = parsed;
          }
          // Same post-processing the legacy path applies to raw history rows:
          // drop pending, sort by markedAt (fallback date) desc, take 5.
          final activity = ((value['recentActivity'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(AttendanceModel.fromJson)
              .where((r) => r.status != AttendanceStatus.pending)
              .toList()
            ..sort((a, b) =>
                (b.markedAt ?? b.date).compareTo(a.markedAt ?? a.date));

          // All parses succeeded — commit atomically (mirrors legacy guards:
          // meals/summaries/activity only apply when groups exist).
          _groups = groups;
          if (organizationName == 'Your Organisation' && _groups.isNotEmpty) {
            _orgName = _groups.length == 1
                ? _groups.first.name
                : '${_groups.length} Groups';
          }
          if (_groups.isEmpty) return true;
          _todayMeals = meals;
          _mealSummaries
            ..clear()
            ..addAll(summaries);
          _deriveCountsFromSummaries();
          _recentActivity = activity.take(5).toList();
          return true;
        } catch (_) {
          return false; // unexpected shape → legacy path takes over
        }
    }
  }

  /// Derives org-wide + per-group present/absent/total from [_mealSummaries]
  /// (single source of truth shared by the overview and legacy load paths).
  void _deriveCountsFromSummaries() {
    int present = 0;
    int absent = 0;
    int total = 0;
    _presentByGroup.clear();
    _absentByGroup.clear();
    _totalByGroup.clear();
    for (final m in _todayMeals) {
      final s = _mealSummaries[m.id];
      if (s == null) continue;
      final gTotal = s.presentCount + s.absentCount + s.skippedCount;
      _presentByGroup[m.groupId] =
          (_presentByGroup[m.groupId] ?? 0) + s.presentCount;
      _absentByGroup[m.groupId] =
          (_absentByGroup[m.groupId] ?? 0) + s.absentCount;
      _totalByGroup[m.groupId] =
          (_totalByGroup[m.groupId] ?? 0) + gTotal;
      present += s.presentCount;
      absent += s.absentCount;
      total += gTotal;
    }
    _presentToday = present;
    _absentToday = absent;
    _todayTotal = total;
  }

  /// Issue #8: restore the saved default group, or default to the first one
  /// so the dashboard opens on a concrete group rather than a vague total.
  /// Call only when [_groups] is non-empty.
  Future<void> _restoreDefaultGroupSelection() async {
    if (_selectedGroupId == null ||
        !_groups.any((g) => g.id == _selectedGroupId)) {
      final saved = await _loadDefaultGroup();
      _selectedGroupId = (saved != null && _groups.any((g) => g.id == saved))
          ? saved
          : _groups.first.id;
    }
  }

  /// Persists the dashboard KPI core for instant cache-first paint next time.
  void _writeDashCache(String dashKey) {
    ResponseCacheService.instance.write(dashKey, {
      'groups': _groups.map((g) => g.toJson()).toList(),
      'meals': _todayMeals.map((m) => m.toJson()).toList(),
      'activity': _recentActivity.map((a) => a.toJson()).toList(),
      'present': _presentToday,
      'absent': _absentToday,
      'total': _todayTotal,
      'presentByGroup': _presentByGroup,
      'absentByGroup': _absentByGroup,
      'totalByGroup': _totalByGroup,
      'selectedGroupId': _selectedGroupId,
    });
  }

  Future<void> refresh({
    required String adminId,
    required String organizationId,
    String name = 'Admin',
    String organizationName = 'Your Organisation',
  }) =>
      load(
        adminId: adminId,
        organizationId: organizationId,
        name: name,
        organizationName: organizationName,
      );

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Start-of-today at midnight for the attendance summary query.
  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Restores an int-valued map from cached JSON (best-effort).
  void _restoreIntMap(Map<String, int> target, dynamic src) {
    target.clear();
    if (src is Map) {
      src.forEach((k, v) {
        if (k is String && v is num) target[k] = v.toInt();
      });
    }
  }

  // ── B10 realtime binding ───────────────────────────────────────────────────

  /// Connects, joins every loaded group room (admins bypass membership
  /// server-side), and subscribes to live events. Idempotent; no-op in mock.
  void _bindRealtime() {
    if (_rtOrgId == null) return;
    RealtimeService.instance.connect();
    for (final g in _groups) {
      if (_rtJoinedGroups.add(g.id)) RealtimeService.instance.joinGroup(g.id);
    }
    _rtSub ??= RealtimeService.instance.events
        .where((m) => _rtEvents.contains(m.name))
        .listen((_) => _scheduleRealtimeRefresh());
  }

  /// Coalesces bursts of events into a single reload.
  void _scheduleRealtimeRefresh() {
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 800), () {
      final adminId = _rtAdminId;
      final orgId = _rtOrgId;
      if (adminId != null && orgId != null && !_isFetching) {
        load(
          adminId: adminId,
          organizationId: orgId,
          name: _rtName,
          organizationName: _rtOrgName,
        );
      }
    });
  }

  @override
  void dispose() {
    _rtDebounce?.cancel();
    _rtSub?.cancel();
    for (final g in _rtJoinedGroups) {
      RealtimeService.instance.leaveGroup(g);
    }
    super.dispose();
  }
}

// ── AdminDashboardScope ─────────────────────────────────────────────────────

/// Provides a shell-level [AdminDashboardProvider] to the admin subtree so all
/// admin tabs share ONE instance. Created once in [AdminShell]; its in-memory
/// state (incl. the non-cacheable meal-wise summaries) survives tab switches —
/// so returning to the dashboard shows the last data instantly instead of
/// flashing zeros (Issue 1). Mirrors `StudentDashboardScope`.
class AdminDashboardScope extends InheritedNotifier<AdminDashboardProvider> {
  const AdminDashboardScope({
    super.key,
    required AdminDashboardProvider notifier,
    required super.child,
  }) : super(notifier: notifier);

  static AdminDashboardProvider of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AdminDashboardScope>();
    assert(scope != null, 'AdminDashboardScope not found in widget tree');
    return scope!.notifier!;
  }

  @override
  bool updateShouldNotify(AdminDashboardScope oldWidget) => true;
}

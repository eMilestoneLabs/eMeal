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
import 'package:smart_meal_management/data/services/selected_group_store.dart';
import 'package:smart_meal_management/data/services/selected_group_subscription.dart';
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
  /// ISSUE-002(vi): the placeholder shown only until a real organisation name
  /// is known. Named so the "is it still unresolved?" test cannot drift from the
  /// default via a typo in one of its several comparison sites.
  static const String kOrgNamePlaceholder = 'Your Organisation';

  String _orgName = kOrgNamePlaceholder;

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
    // Module 22 (FR-HG-064, Pass 9): guest mutations change kitchen counts
    // (meal summaries) live — booked/cancelled/approved/auto-cancelled.
    RealtimeEvents.mealGuestUpdated,
  };

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<GroupModel> get groups => _groups;

  /// Pass 15 (FR-ANL-022): when the shown analytics/KPIs were last refreshed
  /// from the server. Set to the cache timestamp on a cached paint and to
  /// now() when live data lands; drives the FreshnessBadge so a stale cached
  /// dashboard is visibly flagged.
  DateTime? _lastUpdated;
  DateTime? get lastUpdated => _lastUpdated;

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
      ..sort(MealModel.compareChronological);
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
  /// Public so [CacheWarmer] can warm the attendance/members of the group the
  /// admin actually opens on (single source of truth for the prefs key).
  static const String kDefaultGroupKey = 'admin_default_group_id';

  // ISSUE-003 (Live-Test-12): persistence routes through the shared
  // [SelectedGroupStore] so EVERY admin tab (Meals, Attendance, Billing,
  // Exports) follows the same selected group — the store also keeps the
  // legacy unscoped key in sync for CacheWarmer.
  Future<void> _persistDefaultGroup(String? groupId) async {
    final org = _rtOrgId;
    if (org != null && org.isNotEmpty) {
      await SelectedGroupStore.instance.write(org, groupId);
      return;
    }
    // No org context yet — legacy behaviour.
    final prefs = await SharedPreferences.getInstance();
    if (groupId == null) {
      await prefs.remove(kDefaultGroupKey);
    } else {
      await prefs.setString(kDefaultGroupKey, groupId);
    }
  }

  Future<String?> _loadDefaultGroup() async {
    final org = _rtOrgId;
    if (org != null && org.isNotEmpty) {
      return SelectedGroupStore.instance.read(org);
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kDefaultGroupKey);
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
    _rtAdminId = adminId;
    _rtOrgId = organizationId;
    _rtName = name;
    // ISSUE-3A: `organizationName` DEFAULTS to the placeholder, and the caller
    // cannot supply a real one — the user payload carries only organizationId.
    // Assigning it unconditionally wiped an already-resolved organisation name,
    // and `notifyListeners()` below painted that wipe at once: the header fell
    // back to "Your Organisation" on every load, every pull-to-refresh, every
    // refresh-button tap and every error retry.
    //
    // The guard lives HERE, not at the call sites: `refresh()` forwards to this
    // method with the same placeholder default, so fixing callers one by one
    // left the wipe alive on the refresh path. One gate closes it for every
    // caller, present and future. Only a REAL name may overwrite.
    if (organizationName.trim().isNotEmpty &&
        organizationName != kOrgNamePlaceholder) {
      _orgName = organizationName;
      _rtOrgName = organizationName;
    }
    // ISSUE-003: follow app-wide group switches made on any other admin tab.
    _bindGroupSelection(organizationId);
    notifyListeners();

    // Cache-first (stale-while-revalidate): paint last-known KPIs + recent
    // activity instantly; the fetches below overwrite. Atomic + best-effort.
    final dashKey = 'admin_dashboard:$organizationId';
    // Miss-vs-empty aware: a cached EMPTY dashboard (new account, no groups
    // yet) still counts as a valid instant paint — the real empty state shows
    // immediately while the network refresh runs, instead of a skeleton +
    // full round-trip on every tap.
    var paintedFromCache = false;
    if (_groups.isEmpty) {
      final cached = await ResponseCacheService.instance
          .read(dashKey, maxAge: const Duration(hours: 12));
      if (cached is Map) {
        // Pass 15 (FR-ANL-022): remember how old the painted cache is so the
        // freshness badge shows until the live refresh below lands.
        ResponseCacheService.instance.readTimestamp(dashKey).then((ts) {
          if (ts != null && _lastUpdated == null) {
            _lastUpdated = ts;
            notifyListeners();
          }
        });
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
          // Cold-start zeros fix: parse cached per-meal summaries so the
          // meal-wise attendance + preference cards paint last-known values
          // instead of flashing empty until the network responds. Optional
          // key — absent in older caches, in which case nothing changes.
          final summaries = <String, MealAttendanceSummary>{};
          for (final s
              in ((cached['mealSummaries'] as List?) ?? const <dynamic>[])
                  .whereType<Map>()) {
            final parsed =
                MealAttendanceSummary.fromJson(s.cast<String, dynamic>());
            if (parsed.mealId.isNotEmpty) summaries[parsed.mealId] = parsed;
          }
          // All list parses succeeded — assign atomically (no partial state).
          _groups = groups;
          _todayMeals = meals;
          _recentActivity = activity;
          _mealSummaries
            ..clear()
            ..addAll(summaries);
          _presentToday = (cached['present'] as num?)?.toInt() ?? 0;
          _absentToday = (cached['absent'] as num?)?.toInt() ?? 0;
          _todayTotal = (cached['total'] as num?)?.toInt() ?? 0;
          _restoreIntMap(_presentByGroup, cached['presentByGroup']);
          _restoreIntMap(_absentByGroup, cached['absentByGroup']);
          _restoreIntMap(_totalByGroup, cached['totalByGroup']);
          final sg = cached['selectedGroupId'];
          if (sg is String) _selectedGroupId = sg;
          // ISSUE-002(vi): restore the real organisation name on the cold paint.
          //
          // Read from a VERSIONED key. Builds before this fix wrote the
          // group-name / "N Groups" substitution into the old `orgName` key, so
          // an upgrading device still holds a GROUP name there. Restoring that
          // would resurrect the exact defect this batch fixes — a group name in
          // the Organisation field — on the first cold paint after upgrade.
          // Only values written by a build that never substitutes are trusted;
          // the stale key is ignored and disappears on the next cache write.
          final cachedOrg = cached['orgNameV2'];
          if (cachedOrg is String &&
              cachedOrg.trim().isNotEmpty &&
              cachedOrg != kOrgNamePlaceholder) {
            _orgName = cachedOrg;
            _rtOrgName = cachedOrg;
          }
          paintedFromCache = true;
        } catch (_) {/* ignore corrupt cache */}
      }
    }
    _isLoading = _groups.isEmpty && !paintedFromCache;
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
      // Cache the answer even when it is EMPTY (new account) — a cached
      // "no groups yet" paints instantly on the next tap.
      _writeDashCache(dashKey);
      // Pass 15 (FR-ANL-022): live data landed — stamp freshness.
      _lastUpdated = DateTime.now();
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
        // No org-name resolution here: this legacy 3-wave fallback runs only
        // when the overview aggregate failed, and no endpoint on it carries the
        // organisation name. Whatever is already resolved (SWR cache, or an
        // earlier overview) is left untouched rather than replaced.
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

    // Persist the dashboard KPI core for instant cache-first paint next time
    // — even when EMPTY, so a new account's next tap paints instantly.
    _writeDashCache(dashKey);

    // Pass 15 (FR-ANL-022): live data landed via the legacy wave path.
    _lastUpdated = DateTime.now();
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
          // Live-Test-14 ISSUE-002(vi): the dashboard header showed the literal
          // placeholder "Your Organisation" because NO caller ever passed a real
          // name and no endpoint returned one — the group-name substitution
          // below was the only escape hatch, and it displayed a GROUP (or "N
          // Groups") where the user expects the ORGANISATION they named at
          // signup. GET /dashboard/admin/overview now returns
          // `organization: { id, name }`, which is authoritative and wins.
          // Defensive read: a hard `as String?` cast would THROW on an
          // unexpected type, and this whole block is wrapped in a catch that
          // falls back to the 3-wave legacy path — so a malformed name field
          // would silently cost a round-trip. Type-test instead of casting.
          final orgJson = value['organization'];
          final rawOrgName = orgJson is Map ? orgJson['name'] : null;
          final serverOrgName = rawOrgName is String ? rawOrgName.trim() : '';
          if (serverOrgName.isNotEmpty) {
            _orgName = serverOrgName;
            _rtOrgName = serverOrgName;
          }
          // The former `else` branch substituted a GROUP NAME (or "N Groups")
          // into this ORGANISATION field. It read `_groups.first` — never the
          // SELECTED group — so a group switch could not update it, which is
          // the "top section still shows the previous group" report. Removed:
          // the group COUNT it carried is preserved by [AdminGreetingCard],
          // which renders it beside the org name instead of in place of it.
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
    // ISSUE-003: the persisted selection is the single source of truth — a
    // switch made on ANY admin tab (via SelectedGroupStore) wins over the
    // stale selectedGroupId a cached dashboard payload may carry.
    final saved = await _loadDefaultGroup();
    if (saved != null && _groups.any((g) => g.id == saved)) {
      _selectedGroupId = saved;
      return;
    }
    if (_selectedGroupId == null ||
        !_groups.any((g) => g.id == _selectedGroupId)) {
      _selectedGroupId = _groups.first.id;
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
      // Cold-start zeros fix: persist per-meal summaries so the meal-wise
      // cards paint last-known values on the next cache-first paint.
      'mealSummaries':
          _mealSummaries.values.map((s) => s.toJson()).toList(),
      // ISSUE-002(vi): persist the resolved organisation name so the instant
      // cache-first paint greets with the real org instead of flashing the
      // placeholder until the network answers.
      //
      // Versioned key (see the restore side): the legacy `orgName` key could
      // hold a GROUP name written by an older build, so this build neither
      // reads nor writes it. Only a value that is genuinely the organisation
      // — never a group substitution — is stored here.
      'orgNameV2': _orgName,
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

  // ── ISSUE-003 app-wide group selection ─────────────────────────────────────

  SelectedGroupSubscription? _groupSelSub;

  /// Org the subscription above is bound to — an ORG switch must rebind, or
  /// the listener would keep filtering for the previous organisation and
  /// silently stop following group switches.
  String? _groupSelOrgId;

  /// Follow group switches made on ANY other tab (Meals / Weekly Menu /
  /// Attendance / Billing / Exports). Bound once per org from [load]; the
  /// echo of this provider's OWN [selectGroup] write is suppressed by the
  /// isCurrent guard, so switching here never double-reloads.
  void _bindGroupSelection(String organizationId) {
    if (_groupSelSub != null && _groupSelOrgId == organizationId) return;
    _groupSelSub?.cancel();
    _groupSelOrgId = organizationId;
    _groupSelSub = SelectedGroupSubscription.bind(
      organizationId: organizationId,
      isCurrent: (id) => _selectedGroupId == id,
      onChanged: (id) {
        // Only adopt a group this admin actually has — a stale/foreign id is
        // ignored rather than blanking the dashboard.
        if (_groups.isNotEmpty && !_groups.any((g) => g.id == id)) return;
        _selectedGroupId = id;
        notifyListeners();
        // Refresh the group-scoped stats for the new context. Reuses the
        // existing coalesced reload — no new network path, no cache bypass.
        _scheduleRealtimeRefresh();
      },
    );
  }

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
    _groupSelSub?.cancel();
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

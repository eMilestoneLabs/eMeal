import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
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
  })  : _groupRepo = groupRepository ?? GroupRepository(),
        _attendanceRepo = attendanceRepository ?? AttendanceRepository(),
        _mealRepo = mealRepository ?? MealRepository();

  final GroupRepository _groupRepo;
  final AttendanceRepository _attendanceRepo;
  final MealRepository _mealRepo;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;
  List<GroupModel> _groups = [];
  List<MealModel> _todayMeals = [];
  int _presentToday = 0;
  int _absentToday = 0;
  int _todayTotal = 0;
  String _adminName = 'Admin';
  String _orgName = 'Your Organisation';

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

  int get totalMembers => _groups.fold(0, (s, g) => s + g.memberCount);
  int get groupCount => _groups.length;
  int get presentToday => _presentToday;
  int get absentToday => _absentToday;

  double get attendanceRate =>
      _todayTotal == 0 ? 0.0 : _presentToday / _todayTotal;

  List<AttendanceModel> get recentActivity => _recentActivity;

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
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    _adminName = name;
    _orgName = organizationName;
    _rtAdminId = adminId;
    _rtOrgId = organizationId;
    _rtName = name;
    _rtOrgName = organizationName;
    notifyListeners();

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
        notifyListeners();
        return;
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
      final today = _today();
      final now = DateTime.now();

      // 3a. Attendance summaries — parallel fetch, sum counts
      final summaryFutures = _groups.map(
        (g) => _attendanceRepo.getGroupAttendanceSummary(
          groupId: g.id,
          organizationId: organizationId,
          from: today,
          to: now,
        ),
      );
      final summaryResults = await Future.wait(summaryFutures);

      int present = 0;
      int absent = 0;
      int total = 0;
      for (final result in summaryResults) {
        if (result case Ok(:final value)) {
          present += value.presentCount;
          absent += value.absentCount;
          total += value.presentCount + value.absentCount + value.pendingCount;
        }
      }
      _presentToday = present;
      _absentToday = absent;
      _todayTotal = total;

      // 3b. Recent activity feed — fetch from all groups, merge, sort, cap at 5
      final historyFutures = _groups.map(
        (g) => _attendanceRepo.getAttendanceHistory(
          userId: '',
          groupId: g.id,
          organizationId: organizationId,
          from: today,
          to: now,
          params: const PaginationParams(page: 1, limit: 5),
        ),
      );
      final historyResults = await Future.wait(historyFutures);

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

    _isLoading = false;
    notifyListeners();
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
      if (adminId != null && orgId != null && !_isLoading) {
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

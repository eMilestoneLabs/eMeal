import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';

/// State manager for admin attendance management screen.
///
/// Loads group attendance for a selected date, supports status filtering,
/// and date navigation.
class AdminAttendanceProvider extends ChangeNotifier {
  AdminAttendanceProvider({AttendanceRepository? repo})
      : _repo = repo ?? AttendanceRepository();

  final AttendanceRepository _repo;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;
  List<AttendanceModel> _records = [];
  DateTime _selectedDate = DateTime.now();
  AttendanceStatus? _filterStatus;
  // Issue 4: members on vacation, tracked separately from present/absent/pending.
  Set<String> _vacationUserIds = {};
  int _vacationCount = 0;
  // Synthetic onVacation rows (userName snapshot) so the "Vacation" filter can
  // LIST members, not just count them. Never mixed into _records, so present/
  // absent/pending counts stay correct.
  List<AttendanceModel> _vacationRecords = [];

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDate => _selectedDate;
  AttendanceStatus? get filterStatus => _filterStatus;

  List<AttendanceModel> get filteredRecords {
    // The "Vacation" filter lists members on approved vacation for the selected
    // date. They have NO attendance rows (vacation is a separate state, never a
    // per-day onVacation record), so surface the server-computed vacation list
    // here — otherwise the filter would show empty despite Vacation = N.
    if (_filterStatus == AttendanceStatus.onVacation) return _vacationRecords;
    if (_filterStatus == null) return _records;
    return _records.where((r) => r.status == _filterStatus).toList();
  }

  int get totalCount => _records.length;
  int get presentCount =>
      _records.where((r) => r.status == AttendanceStatus.present).length;
  int get absentCount =>
      _records.where((r) => r.status == AttendanceStatus.absent).length;
  int get pendingCount =>
      _records.where((r) => r.status == AttendanceStatus.pending).length;

  // Issue 4: count of members currently on vacation in this group. They are not
  // counted as present/absent/pending — vacation is a separate state.
  int get vacationCount => _vacationCount;
  Set<String> get vacationUserIds => _vacationUserIds;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load({
    required String groupId,
    required String organizationId,
  }) async {
    // Cache-first: paint last-known records instantly, then refresh.
    final cacheKey =
        'admin_attendance:$organizationId:$groupId:${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}';
    if (_records.isEmpty) {
      _isLoading = true; // sync: first build shows the loader, never "No records found"
      // Miss-vs-empty aware: a cached EMPTY day (e.g. every morning before
      // anyone marks) paints instantly too; only a true cache MISS keeps the
      // loader while the network fetch below runs.
      final cached = await ResponseCacheService.instance.readListOrNull(
          cacheKey, AttendanceModel.fromJson, maxAge: const Duration(hours: 12));
      if (cached != null) {
        _records = cached;
        _isLoading = false;
      }
    } else {
      _isLoading = false;
    }
    _error = null;
    notifyListeners();

    // Fetch the date-scoped vacation set IN PARALLEL with attendance so the
    // spinner waits for one round-trip, not two. The "Vacation = N" count lands
    // a moment later and updates in place. It reflects members on APPROVED
    // vacation covering the SELECTED DATE (server-computed, slot-aware) — the
    // global isVacationMode flag was date-agnostic and stayed 0 for future or
    // past-dated approvals.
    final vacationFuture = _repo.getGroupVacationMembers(
      groupId: groupId,
      date: _selectedDate,
    );

    final result = await _repo.getGroupAttendance(
      groupId: groupId,
      organizationId: organizationId,
      date: _selectedDate,
    );

    switch (result) {
      case Ok(:final value):
        _records = value;
        ResponseCacheService.instance
            .writeList(cacheKey, value, (r) => r.toJson());
      case Err(:final failure):
        _error = failure.message;
    }

    // Records are in — drop the spinner now; the vacation count updates when its
    // parallel fetch lands below.
    _isLoading = false;
    notifyListeners();

    // Surface a separate "Vacation = X" count. Members on vacation are tracked
    // apart from present/absent/pending (they are not absentees). On failure the
    // count is left untouched rather than reset, so a transient error can't blank
    // a previously-correct number.
    final vacationResult = await vacationFuture;
    if (vacationResult case Ok(:final value)) {
      _vacationUserIds = value.map((m) => m.id).toSet();
      _vacationCount = value.length;
      // Build synthetic rows so the "Vacation" filter lists these members.
      _vacationRecords = value
          .map((m) => AttendanceModel(
                id: 'vac_${m.id}',
                mealId: '',
                userId: m.id,
                groupId: groupId,
                organizationId: organizationId,
                status: AttendanceStatus.onVacation,
                date: _selectedDate,
                userName: m.name,
              ))
          .toList();
      notifyListeners();
    }
  }

  // ── Filters ────────────────────────────────────────────────────────────────

  void setFilter(AttendanceStatus? status) {
    _filterStatus = status;
    notifyListeners();
  }

  void setDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  // SRS Module 03 ATT-004: the admin override write path was REMOVED —
  // attendance ownership belongs to the member; post-window changes flow
  // exclusively through the Correction Request approve/reject workflow.

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

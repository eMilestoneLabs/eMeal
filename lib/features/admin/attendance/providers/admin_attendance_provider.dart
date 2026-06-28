import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';

/// State manager for admin attendance management screen.
///
/// Loads group attendance for a selected date, supports status filtering,
/// and date navigation.
class AdminAttendanceProvider extends ChangeNotifier {
  AdminAttendanceProvider({AttendanceRepository? repo, GroupRepository? groupRepo})
      : _repo = repo ?? AttendanceRepository(),
        _groupRepo = groupRepo ?? GroupRepository();

  final AttendanceRepository _repo;
  final GroupRepository _groupRepo;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;
  List<AttendanceModel> _records = [];
  DateTime _selectedDate = DateTime.now();
  AttendanceStatus? _filterStatus;
  // Issue 4: members on vacation, tracked separately from present/absent/pending.
  Set<String> _vacationUserIds = {};
  int _vacationCount = 0;

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDate => _selectedDate;
  AttendanceStatus? get filterStatus => _filterStatus;

  List<AttendanceModel> get filteredRecords {
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
      _records = await ResponseCacheService.instance.readList(
          cacheKey, AttendanceModel.fromJson, maxAge: const Duration(hours: 12));
    }
    _isLoading = _records.isEmpty;
    _error = null;
    notifyListeners();

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

    // Issue 4: surface a separate "Vacation = X" count. Members on vacation are
    // tracked apart from present/absent/pending (they are not absentees).
    final membersResult = await _groupRepo.getGroupMembers(
      organizationId: organizationId,
      groupId: groupId,
    );
    if (membersResult case Ok(:final value)) {
      final onVacation =
          value.data.where((u) => u.isVacationMode).map((u) => u.id).toSet();
      _vacationUserIds = onVacation;
      _vacationCount = onVacation.length;
    }

    _isLoading = false;
    notifyListeners();
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

  // ── Admin override ────────────────────────────────────────────────────────

  /// Marks a specific attendance record with [newStatus], regardless of timing
  /// window. This is the admin override path — bypasses all window checks.
  ///
  /// Applies an optimistic update so the list reflects the change immediately.
  Future<bool> markAttendance({
    required String recordId,
    required AttendanceStatus newStatus,
  }) async {
    final idx = _records.indexWhere((r) => r.id == recordId);
    if (idx == -1) return false;
    final original = _records[idx];

    // Optimistic update — swap status + set markedAt to now.
    final optimistic = original.copyWith(
      status: newStatus,
      markedAt: DateTime.now(),
    );
    _records = List.of(_records)..[idx] = optimistic;
    notifyListeners();

    // Issue 6: actually PERSIST the override (this was previously a local-only
    // no-op). The admin override endpoint bypasses the window + vacation checks
    // and snapshots the effective price — so a forgotten student can be marked
    // even after the window has closed, and it sticks across reloads.
    final result = await _repo.adminOverride(
      record: original.copyWith(status: newStatus),
    );
    switch (result) {
      case Ok(:final value):
        final i = _records.indexWhere((r) => r.id == recordId);
        if (i != -1) {
          _records = List.of(_records)..[i] = value;
          notifyListeners();
        }
        return true;
      case Err(:final failure):
        // Revert the optimistic change and surface the error.
        final i = _records.indexWhere((r) => r.id == recordId);
        if (i != -1) {
          _records = List.of(_records)..[i] = original;
        }
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

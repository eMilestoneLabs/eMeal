import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

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

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load({
    required String groupId,
    required String organizationId,
  }) async {
    _isLoading = true;
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
      case Err(:final failure):
        _error = failure.message;
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

    // Optimistic update — swap status + set markedAt to now
    final updated = _records[idx].copyWith(
      status: newStatus,
      markedAt: DateTime.now(),
    );
    _records = List.of(_records)..[idx] = updated;
    notifyListeners();

    // Simulate network latency — in production, call the API here
    await Future.delayed(const Duration(milliseconds: 300));
    return true;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

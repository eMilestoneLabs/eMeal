import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Student attendance state manager with optimistic update + rollback.
class StudentAttendanceProvider extends ChangeNotifier {
  StudentAttendanceProvider({AttendanceRepository? repo})
      : _repo = repo ?? AttendanceRepository();

  final AttendanceRepository _repo;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;
  List<AttendanceModel> _records = [];

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<AttendanceModel> get records => _records;

  AttendanceStatus? statusForMeal(String mealId) {
    try {
      final today = DateTime.now();
      return _records
          .firstWhere(
            (r) =>
                r.mealId == mealId &&
                r.date.year == today.year &&
                r.date.month == today.month &&
                r.date.day == today.day,
          )
          .status;
    } catch (_) {
      return null;
    }
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load({
    required String userId,
    required String groupId,
    required String organizationId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repo.getTodayAttendance(
      userId: userId,
      groupId: groupId,
      organizationId: organizationId,
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

  // ── Mark attendance with optimistic update ─────────────────────────────────

  Future<bool> markAttendance({
    required String mealId,
    required String userId,
    required String groupId,
    required String organizationId,
    required AttendanceStatus status,
    String? preference,
  }) async {
    final today = DateTime.now();

    // Find existing record if any
    final existingIdx = _records.indexWhere(
      (r) =>
          r.mealId == mealId &&
          r.date.year == today.year &&
          r.date.month == today.month &&
          r.date.day == today.day,
    );

    // Optimistic update
    final optimistic = existingIdx != -1
        ? _records[existingIdx].copyWith(
            status: status,
            preference: preference,
            markedAt: today,
          )
        : AttendanceModel(
            id: 'temp_${mealId}_${today.millisecondsSinceEpoch}',
            mealId: mealId,
            userId: userId,
            groupId: groupId,
            organizationId: organizationId,
            status: status,
            date: today,
            markedAt: today,
            preference: preference,
          );

    final snapshot = List<AttendanceModel>.from(_records);
    if (existingIdx != -1) {
      _records[existingIdx] = optimistic;
    } else {
      _records.add(optimistic);
    }
    notifyListeners();

    // Persist
    final result = await _repo.markAttendance(record: optimistic);
    switch (result) {
      case Ok(:final value):
        final idx = _records.indexWhere((r) => r.id == optimistic.id);
        if (idx != -1) _records[idx] = value;
        notifyListeners();
        return true;
      case Err(:final failure):
        // Rollback
        _records = snapshot;
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

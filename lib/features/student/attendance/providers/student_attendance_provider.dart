import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';

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
    // Cache-first (stale-while-revalidate): paint last-known today-records
    // instantly, then refresh below. Best-effort; the fetch always wins.
    final cacheKey = _attendanceCacheKey(organizationId, groupId, userId);
    bool cacheMiss = false;
    if (_records.isEmpty) {
      // Miss-vs-empty aware: a cached EMPTY day (nothing marked yet) paints
      // instantly; only a true cache MISS keeps the loader while the network
      // fetch below runs.
      final cached = await ResponseCacheService.instance.readListOrNull(
          cacheKey, AttendanceModel.fromJson, maxAge: const Duration(hours: 12));
      if (cached != null) {
        _records = cached;
      } else {
        cacheMiss = true;
      }
    }
    _isLoading = cacheMiss && _records.isEmpty;
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
        ResponseCacheService.instance
            .writeList(cacheKey, value, (r) => r.toJson());
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Per-user, per-day cache key for today's attendance records.
  String _attendanceCacheKey(String orgId, String groupId, String userId) {
    final d = DateTime.now();
    return 'attendance_today:$orgId:$groupId:$userId:${d.year}-${d.month}-${d.day}';
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

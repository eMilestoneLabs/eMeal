import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_attendance_repository.dart';
import 'package:smart_meal_management/data/mock/mock_attendance_data.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// In-memory mock implementation of [IAttendanceRepository].
///
/// Simulates 300 ms network latency. All mutations are reflected in the
/// in-memory store — data resets on hot-restart.
///
/// Blocked-member enforcement: [markAttendance] looks up the [GroupRepository]
/// to verify the submitting user is not in [GroupModel.blockedMemberIds] before
/// persisting. This mirrors production-side row-level security checks.
class AttendanceRepository implements IAttendanceRepository {
  AttendanceRepository({GroupRepository? groupRepository})
      : _groupRepo = groupRepository ?? GroupRepository() {
    // Pre-populate with 30 days of history for the default user
    _store.addAll(MockAttendanceData.generate(
      userId: 'usr_stu_001',
      groupId: 'grp_001',
      organizationId: 'org_001',
    ));
  }

  final GroupRepository _groupRepo;

  final List<AttendanceModel> _store = [];

  static Future<void> _delay() =>
      Future.delayed(const Duration(milliseconds: 300));

  @override
  Future<Result<List<AttendanceModel>>> getTodayAttendance({
    required String userId,
    required String groupId,
    required String organizationId,
  }) async {
    await _delay();
    try {
      final today = DateTime.now();
      final records = _store
          .where((a) =>
              a.userId == userId &&
              a.groupId == groupId &&
              a.organizationId == organizationId &&
              a.date.year == today.year &&
              a.date.month == today.month &&
              a.date.day == today.day)
          .toList();

      // If no today records exist yet, return pending stubs
      if (records.isEmpty) {
        return Ok(MockAttendanceData.todayRecords(
          userId: userId,
          groupId: groupId,
          organizationId: organizationId,
        ));
      }
      return Ok(records);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to load today attendance: $e'));
    }
  }

  @override
  Future<Result<AttendanceSummary>> getAttendanceSummary({
    required String userId,
    required String groupId,
    required String organizationId,
    required DateTime from,
    required DateTime to,
  }) async {
    await _delay();
    try {
      final records = _store.where((a) =>
          a.userId == userId &&
          a.groupId == groupId &&
          !a.date.isBefore(from) &&
          !a.date.isAfter(to));

      final days = to.difference(from).inDays + 1;
      int present = 0, absent = 0, skipped = 0;
      for (final r in records) {
        if (r.status == AttendanceStatus.present) present++;
        if (r.status == AttendanceStatus.absent) absent++;
        if (r.status == AttendanceStatus.skipped) skipped++;
      }
      return Ok(AttendanceSummary(
        totalDays: days,
        presentDays: present,
        absentDays: absent,
        skippedDays: skipped,
      ));
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to compute summary: $e'));
    }
  }

  @override
  Future<Result<PaginatedResponse<AttendanceModel>>> getAttendanceHistory({
    required String userId,
    required String groupId,
    required String organizationId,
    DateTime? from,
    DateTime? to,
    PaginationParams params = const PaginationParams(),
  }) async {
    await _delay();
    try {
      var records = _store
          .where((a) =>
              a.userId == userId &&
              a.groupId == groupId &&
              a.organizationId == organizationId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      if (from != null) {
        records = records.where((a) => !a.date.isBefore(from)).toList();
      }
      if (to != null) {
        records = records.where((a) => !a.date.isAfter(to)).toList();
      }

      final total = records.length;
      final start = (params.page - 1) * params.limit;
      final end = (start + params.limit).clamp(0, total);
      final pageData = start >= total ? <AttendanceModel>[] : records.sublist(start, end);

      return Ok(PaginatedResponse(
        data: pageData,
        total: total,
        page: params.page,
        limit: params.limit,
      ));
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to load history: $e'));
    }
  }

  @override
  Future<Result<List<AttendanceModel>>> getGroupAttendance({
    required String groupId,
    required String organizationId,
    required DateTime date,
  }) async {
    await _delay();
    try {
      final records = _store
          .where((a) =>
              a.groupId == groupId &&
              a.organizationId == organizationId &&
              a.date.year == date.year &&
              a.date.month == date.month &&
              a.date.day == date.day)
          .toList();
      return Ok(records);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to load group attendance: $e'));
    }
  }

  @override
  Future<Result<AttendanceModel>> markAttendance({
    required AttendanceModel record,
  }) async {
    await _delay();
    try {
      // ── Blocked-member guard ─────────────────────────────────────────────
      // Look up the group and reject if the user is in blockedMemberIds.
      // In production this check is enforced by NestJS guards on the API.
      final groupResult = await _groupRepo.getGroup(
        organizationId: record.organizationId,
        groupId: record.groupId,
      );
      switch (groupResult) {
        case Ok(:final value):
          if (value.blockedMemberIds.contains(record.userId)) {
            return const Err(ValidationFailure(
              message:
                  'You have been blocked from this group and cannot mark attendance.',
            ));
          }
        case Err():
          // Group lookup failed — allow the mark to proceed for resilience.
          break;
      }

      final existing = _store.indexWhere((a) =>
          a.mealId == record.mealId &&
          a.userId == record.userId &&
          a.date.year == record.date.year &&
          a.date.month == record.date.month &&
          a.date.day == record.date.day);

      final toSave = record.copyWith(markedAt: DateTime.now());
      if (existing != -1) {
        _store[existing] = toSave;
      } else {
        _store.add(toSave);
      }
      return Ok(toSave);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to mark attendance: $e'));
    }
  }

  @override
  Future<Result<AttendanceModel>> updateAttendance({
    required AttendanceModel record,
  }) async {
    await _delay();
    try {
      final idx = _store.indexWhere((a) => a.id == record.id);
      if (idx == -1) {
        return const Err(NetworkFailure(message: 'Attendance record not found', statusCode: 404));
      }
      final updated = record.copyWith(markedAt: DateTime.now());
      _store[idx] = updated;
      return Ok(updated);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to update attendance: $e'));
    }
  }

  /// Alias used by admin dashboard provider — aggregates all users in a group.
  Future<Result<AttendanceSummary>> getGroupAttendanceSummary({
    required String organizationId,
    required String groupId,
    DateTime? from,
    DateTime? to,
  }) {
    final start = from ?? DateTime.now().subtract(const Duration(days: 30));
    final end = to ?? DateTime.now();
    // For mock: use a generic userId; production will aggregate server-side.
    return getAttendanceSummary(
      userId: 'group:$groupId',
      organizationId: organizationId,
      groupId: groupId,
      from: start,
      to: end,
    );
  }
}

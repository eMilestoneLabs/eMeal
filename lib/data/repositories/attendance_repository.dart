import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_attendance_repository.dart';
import 'package:smart_meal_management/data/mock/mock_attendance_data.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Attendance repository with dual-mode dispatch based on
/// [EnvConfig.mockAuthEnabled].
///
/// ## Live mode ([EnvConfig.mockAuthEnabled] == false — B10 default)
/// Calls the NestJS backend via [DioApiService]:
///   - GET   /attendance/today?groupId=                      → today's records
///   - GET   /attendance/summary?groupId=&userId=&fromDate=&toDate= → summary
///   - GET   /attendance/history?groupId=&userId=&...&page=&limit=   → history
///   - GET   /attendance?groupId=&fromDate=&toDate=          → group/day records
///   - POST  /attendance                                     → mark (idempotent)
///   - PATCH /attendance/:id                                 → update record
///
/// Dates cross the wire as YYYY-MM-DD strings (MarkAttendanceDto contract).
/// Blocked-member and attendance-window enforcement happen server-side in
/// live mode; the mock branch reproduces the blocked-member guard locally.
///
/// ## Mock mode ([EnvConfig.mockAuthEnabled] == true — instant rollback)
/// In-memory store seeded with 30 days of history. 300 ms simulated latency.
class AttendanceRepository implements IAttendanceRepository {
  AttendanceRepository({GroupRepository? groupRepository})
      : _groupRepo = groupRepository ?? GroupRepository() {
    if (_isMock) {
      // Pre-populate with 30 days of history for the default user (mock only).
      _store.addAll(MockAttendanceData.generate(
        userId: 'usr_stu_001',
        groupId: 'grp_001',
        organizationId: 'org_001',
      ));
    }
  }

  /// B10: live/mock dispatch — same single switch as the other repositories.
  static bool get _isMock => EnvConfig.current.mockAuthEnabled;

  final GroupRepository _groupRepo;

  final List<AttendanceModel> _store = [];

  static Future<void> _delay() =>
      Future.delayed(const Duration(milliseconds: 300));

  /// Formats a [DateTime] as a YYYY-MM-DD string (MarkAttendanceDto contract).
  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Whether a status is one the backend accepts for a mark/update request.
  static bool _isMarkableStatus(AttendanceStatus s) =>
      s == AttendanceStatus.present ||
      s == AttendanceStatus.absent ||
      s == AttendanceStatus.skipped;

  /// Builds the POST/PATCH body for marking attendance (MarkAttendanceDto).
  static Map<String, dynamic> _markBody(AttendanceModel record) => {
        'mealId': record.mealId,
        'attendanceDate': _dateOnly(record.date),
        if (_isMarkableStatus(record.status)) 'status': record.status.name,
        if (record.preference != null) 'preference': record.preference,
        if (record.note != null) 'note': record.note,
      };

  /// Merges the backend's compact mark-response into the submitted [record]
  /// so callers receive a complete [AttendanceModel] (the mark response omits
  /// userId/groupId/organizationId/mealName — those are carried from input).
  static AttendanceModel _mergeMarkResponse(
    AttendanceModel record,
    Map<String, dynamic> j,
  ) {
    return AttendanceModel(
      id: (j['id'] ?? record.id).toString(),
      mealId: (j['mealId'] ?? record.mealId).toString(),
      userId: record.userId,
      groupId: record.groupId,
      organizationId: record.organizationId,
      status: AttendanceStatus.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => record.status,
      ),
      date: j['date'] != null ? DateTime.parse(j['date']) : record.date,
      markedAt:
          j['markedAt'] != null ? DateTime.parse(j['markedAt']) : DateTime.now(),
      preference: j['preference'] ?? record.preference,
      note: record.note,
      mealName: record.mealName,
    );
  }

  @override
  Future<Result<List<AttendanceModel>>> getTodayAttendance({
    required String userId,
    required String groupId,
    required String organizationId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: GET /attendance/today — current user's records for today.
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance/today',
        queryParameters: {'groupId': groupId},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          Ok(PaginatedResponse.fromJson(value, AttendanceModel.fromJson).data),
      };
    }
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
    if (!_isMock) {
      // B10 LIVE: GET /attendance/summary — presentDays/absentDays/skippedDays.
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance/summary',
        queryParameters: {
          'groupId': groupId,
          'userId': userId,
          'fromDate': _dateOnly(from),
          'toDate': _dateOnly(to),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(AttendanceSummary.fromJson(value)),
      };
    }
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
    if (!_isMock) {
      // B10 LIVE: GET /attendance/history — paginated {data,total,page,limit}.
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance/history',
        queryParameters: {
          'groupId': groupId,
          'userId': userId,
          if (from != null) 'fromDate': _dateOnly(from),
          if (to != null) 'toDate': _dateOnly(to),
          'page': params.page.toString(),
          'limit': params.limit.toString(),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          Ok(PaginatedResponse.fromJson(value, AttendanceModel.fromJson)),
      };
    }
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
    if (!_isMock) {
      // B10 LIVE: GET /attendance — admin view of a group on a single date.
      final ds = _dateOnly(date);
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance',
        queryParameters: {
          'groupId': groupId,
          'fromDate': ds,
          'toDate': ds,
          'page': '1',
          'limit': '100',
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          Ok(PaginatedResponse.fromJson(value, AttendanceModel.fromJson).data),
      };
    }
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
    if (!_isMock) {
      // B10 LIVE: POST /attendance — idempotent upsert by userId+mealId+date.
      // Blocked-member + attendance-window rules enforced server-side.
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/attendance',
        body: _markBody(record),
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(_mergeMarkResponse(record, value)),
      };
    }
    await _delay();
    try {
      // Blocked-member guard (mock-side mirror of server row-level security).
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
    if (!_isMock) {
      // B10 LIVE: PATCH /attendance/:id — reuses idempotent mark semantics.
      final result = await DioApiService.instance.patch<Map<String, dynamic>>(
        '/attendance/${record.id}',
        body: _markBody(record),
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(_mergeMarkResponse(record, value)),
      };
    }
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

  /// Alias used by admin dashboard provider — group-level attendance summary.
  ///
  /// Live mode queries GET /attendance/summary scoped to [groupId]; mock mode
  /// aggregates the in-memory store.
  Future<Result<AttendanceSummary>> getGroupAttendanceSummary({
    required String organizationId,
    required String groupId,
    DateTime? from,
    DateTime? to,
  }) async {
    final start = from ?? DateTime.now().subtract(const Duration(days: 30));
    final end = to ?? DateTime.now();
    if (!_isMock) {
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance/summary',
        queryParameters: {
          'groupId': groupId,
          'fromDate': _dateOnly(start),
          'toDate': _dateOnly(end),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(AttendanceSummary.fromJson(value)),
      };
    }
    return getAttendanceSummary(
      userId: 'group:$groupId',
      organizationId: organizationId,
      groupId: groupId,
      from: start,
      to: end,
    );
  }
}

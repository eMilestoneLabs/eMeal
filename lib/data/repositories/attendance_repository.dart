import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_attendance_repository.dart';
import 'package:smart_meal_management/data/mock/mock_attendance_data.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/billing_series.dart';
import 'package:smart_meal_management/shared/models/billing_summary.dart';
import 'package:smart_meal_management/shared/models/meal_attendance_summary.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Attendance repository with dual-mode dispatch based on
/// [EnvConfig.mockAuthEnabled].
class AttendanceRepository implements IAttendanceRepository {
  AttendanceRepository({GroupRepository? groupRepository})
      : _groupRepo = groupRepository ?? GroupRepository() {
    if (_isMock) {
      _store.addAll(MockAttendanceData.generate(
        userId: 'usr_stu_001',
        groupId: 'grp_001',
        organizationId: 'org_001',
      ));
    }
  }

  static bool get _isMock => EnvConfig.current.mockAuthEnabled;

  final GroupRepository _groupRepo;

  final List<AttendanceModel> _store = [];

  static Future<void> _delay() =>
      Future.delayed(const Duration(milliseconds: 300));

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static bool _isMarkableStatus(AttendanceStatus s) =>
      s == AttendanceStatus.present ||
      s == AttendanceStatus.absent ||
      s == AttendanceStatus.skipped;

  static Map<String, dynamic> _markBody(AttendanceModel record) => {
        'mealId': record.mealId,
        'attendanceDate': _dateOnly(record.date),
        if (_isMarkableStatus(record.status)) 'status': record.status.name,
        if (record.preference != null) 'preference': record.preference,
        if (record.note != null) 'note': record.note,
      };

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
      price: j['price'] is int
          ? j['price'] as int
          : (j['price'] != null
              ? int.tryParse(j['price'].toString())
              : record.price),
    );
  }

  @override
  Future<Result<List<AttendanceModel>>> getTodayAttendance({
    required String userId,
    required String groupId,
    required String organizationId,
  }) async {
    if (!_isMock) {
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
  Future<Result<AttendanceModel>> adminOverride({
    required AttendanceModel record,
  }) async {
    if (!_isMock) {
      // Issue 6/5: persist an admin override (bypasses window + vacation; the
      // backend snapshots the effective price). Works for any member and for
      // the admin marking their own attendance.
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/attendance/admin/override',
        body: {
          'userId': record.userId,
          'mealId': record.mealId,
          'attendanceDate': _dateOnly(record.date),
          'status': record.status.name,
          if (record.preference != null) 'preference': record.preference,
          if (record.note != null) 'note': record.note,
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(_mergeMarkResponse(record, value)),
      };
    }
    await _delay();
    final toSave = record.copyWith(markedAt: DateTime.now());
    final existing = _store.indexWhere((a) =>
        a.mealId == record.mealId &&
        a.userId == record.userId &&
        a.date.year == record.date.year &&
        a.date.month == record.date.month &&
        a.date.day == record.date.day);
    if (existing != -1) {
      _store[existing] = toSave;
    } else {
      _store.add(toSave);
    }
    return Ok(toSave);
  }

  @override
  Future<Result<AttendanceModel>> updateAttendance({
    required AttendanceModel record,
  }) async {
    if (!_isMock) {
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

  /// Member Billing V2 — group-wide billing aggregation (admin).
  Future<Result<BillingSummaryV2>> getBillingSummaryV2({
    required String organizationId,
    required String groupId,
    required DateTime from,
    required DateTime to,
  }) async {
    if (!_isMock) {
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance/billing-summary',
        queryParameters: {
          'groupId': groupId,
          'fromDate': _dateOnly(from),
          'toDate': _dateOnly(to),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(BillingSummaryV2.fromJson(value)),
      };
    }

    await _delay();
    try {
      final recs = _store.where((a) =>
          a.groupId == groupId &&
          a.organizationId == organizationId &&
          !a.date.isBefore(DateTime(from.year, from.month, from.day)) &&
          !a.date.isAfter(DateTime(to.year, to.month, to.day)));

      final byUser = <String, List<AttendanceModel>>{};
      for (final r in recs) {
        byUser.putIfAbsent(r.userId, () => []).add(r);
      }

      int revenue = 0, present = 0, skipped = 0, absent = 0;
      final byMeal = <String, List<int>>{};
      final mealName = <String, String>{};
      final members = <BillingMemberRow>[];

      byUser.forEach((uid, list) {
        int p = 0, s = 0, a = 0, bill = 0;
        DateTime? last;
        for (final r in list) {
          switch (r.status) {
            case AttendanceStatus.present:
              p++;
              present++;
              final price = r.price ?? 0;
              bill += price;
              revenue += price;
              final m = byMeal.putIfAbsent(r.mealId, () => [0, 0]);
              m[0] += price;
              m[1] += 1;
              mealName[r.mealId] = r.mealName ?? '—';
            case AttendanceStatus.absent:
              a++;
              absent++;
            case AttendanceStatus.skipped:
              s++;
              skipped++;
            default:
              break;
          }
          if (r.markedAt != null &&
              (last == null || r.markedAt!.isAfter(last))) {
            last = r.markedAt;
          }
        }
        members.add(BillingMemberRow(
          userId: uid,
          userName: list.first.userName ?? uid,
          role: 'member',
          totalBill: bill,
          presentCount: p,
          skippedCount: s,
          absentCount: a,
          lastActivity: last,
        ));
      });

      members.sort((x, y) => y.totalBill.compareTo(x.totalBill));
      final breakdown = byMeal.entries
          .map((e) => BillingMealBreakdown(
                mealId: e.key,
                mealName: mealName[e.key] ?? '—',
                revenue: e.value[0],
                presentCount: e.value[1],
              ))
          .toList()
        ..sort((x, y) => y.revenue.compareTo(x.revenue));

      return Ok(BillingSummaryV2(
        revenue: revenue,
        memberCount: members.length,
        presentMeals: present,
        skippedMeals: skipped,
        absentMeals: absent,
        averageBill: members.isEmpty ? 0 : (revenue / members.length).round(),
        mealBreakdown: breakdown,
        members: members,
      ));
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to load billing: $e'));
    }
  }

  /// Member Billing analytics — bucketed revenue/present-meal time series.
  Future<Result<BillingSeries>> getBillingSeries({
    required String organizationId,
    required String groupId,
    required DateTime from,
    required DateTime to,
    required String bucket,
  }) async {
    if (!_isMock) {
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance/billing-series',
        queryParameters: {
          'groupId': groupId,
          'fromDate': _dateOnly(from),
          'toDate': _dateOnly(to),
          'bucket': bucket,
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(BillingSeries.fromJson(value)),
      };
    }

    await _delay();
    try {
      final recs = _store.where((a) =>
          a.groupId == groupId &&
          a.organizationId == organizationId &&
          a.status == AttendanceStatus.present &&
          !a.date.isBefore(DateTime(from.year, from.month, from.day)) &&
          !a.date.isAfter(DateTime(to.year, to.month, to.day)));
      String pad(int n) => n.toString().padLeft(2, '0');
      String keyOf(DateTime d) {
        if (bucket == 'month') return '${d.year}-${pad(d.month)}';
        if (bucket == 'week') {
          final monday = d.subtract(Duration(days: d.weekday - 1));
          return '${monday.year}-${pad(monday.month)}-${pad(monday.day)}';
        }
        return '${d.year}-${pad(d.month)}-${pad(d.day)}';
      }

      final byKey = <String, List<int>>{}; // key -> [revenue, presentMeals]
      for (final r in recs) {
        final k = keyOf(r.date);
        final agg = byKey.putIfAbsent(k, () => [0, 0]);
        agg[0] += r.price ?? 0;
        agg[1] += 1;
      }
      final points = byKey.entries
          .map((e) => BillingSeriesPoint(
              label: e.key, revenue: e.value[0], presentMeals: e.value[1]))
          .toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      return Ok(BillingSeries(bucket: bucket, points: points));
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to load billing series: $e'));
    }
  }

  /// Per-meal attendance + preference summary for a single date (admin).
  Future<Result<MealAttendanceSummary>> getMealAttendanceSummary({
    required String organizationId,
    required String mealId,
    DateTime? date,
  }) async {
    final day = date ?? DateTime.now();
    if (!_isMock) {
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/attendance/meal-summary',
        queryParameters: {
          'mealId': mealId,
          'date': _dateOnly(day),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(MealAttendanceSummary.fromJson(value)),
      };
    }
    await _delay();
    try {
      final records = _store.where((a) =>
          a.mealId == mealId &&
          a.organizationId == organizationId &&
          a.date.year == day.year &&
          a.date.month == day.month &&
          a.date.day == day.day);
      int present = 0, absent = 0, skipped = 0;
      final breakdown = <String, int>{};
      for (final r in records) {
        switch (r.status) {
          case AttendanceStatus.present:
            present++;
            final p = r.preference;
            if (p != null && p.isNotEmpty) {
              breakdown[p] = (breakdown[p] ?? 0) + 1;
            }
          case AttendanceStatus.absent:
            absent++;
          case AttendanceStatus.skipped:
            skipped++;
          default:
            break;
        }
      }
      return Ok(MealAttendanceSummary(
        mealId: mealId,
        slotKey: '',
        mealName: '',
        date: _dateOnly(day),
        totalMembers: present + absent + skipped,
        presentCount: present,
        absentCount: absent,
        skippedCount: skipped,
        preferenceBreakdown: breakdown,
      ));
    } catch (e) {
      return Err(UnexpectedFailure(
          message: 'Failed to load meal summary: $e'));
    }
  }
}

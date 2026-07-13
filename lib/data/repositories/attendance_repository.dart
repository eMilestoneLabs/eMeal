import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_attendance_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/billing_series.dart';
import 'package:smart_meal_management/shared/models/billing_summary.dart';
import 'package:smart_meal_management/shared/models/meal_attendance_summary.dart';
import 'package:smart_meal_management/shared/models/my_billing.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Attendance repository — calls the live NestJS backend via [DioApiService].
class AttendanceRepository implements IAttendanceRepository {
  AttendanceRepository();

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
        // Module 36 (FR-PG-031): multi-group selections travel only when the
        // meal carries explicit preference groups (server validates).
        if (record.selections != null)
          'selections': record.selections!.map((s) => s.toJson()).toList(),
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
      // Module 36: server-confirmed selection snapshot (null = legacy meal).
      preferences:
          j['preferences'] is List ? j['preferences'] as List<dynamic> : null,
    );
  }

  @override
  Future<Result<Map<String, dynamic>>> getRecordHistory({
    required String recordId,
  }) async {
    // SRS FR-TRUST-010 (Pass 7): member-visible change history.
    return DioApiService.instance.get<Map<String, dynamic>>(
      '/attendance/$recordId/history',
    );
  }

  @override
  Future<Result<List<AttendanceModel>>> getTodayAttendance({
    required String userId,
    required String groupId,
    required String organizationId,
  }) async {
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

  @override
  Future<Result<AttendanceSummary>> getAttendanceSummary({
    required String userId,
    required String groupId,
    required String organizationId,
    required DateTime from,
    required DateTime to,
  }) async {
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

  @override
  Future<Result<PaginatedResponse<AttendanceModel>>> getAttendanceHistory({
    required String userId,
    required String groupId,
    required String organizationId,
    DateTime? from,
    DateTime? to,
    PaginationParams params = const PaginationParams(),
  }) async {
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

  /// Members on APPROVED vacation covering [date] for [groupId] (day-level).
  /// Powers the admin attendance dashboard "Vacation = N" summary AND the
  /// "Vacation" filter list — the count/list reflect the SELECTED DATE
  /// (server-computed, slot-aware) instead of a global per-user flag.
  /// Returns (userId, name) pairs.
  Future<Result<List<({String id, String name})>>> getGroupVacationMembers({
    required String groupId,
    required DateTime date,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/attendance/vacation-members',
      queryParameters: {'groupId': groupId, 'date': _dateOnly(date)},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(
          ((value['members'] as List?) ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map((m) => (
                    id: (m['userId'] ?? '').toString(),
                    name: (m['name'] ?? 'Member').toString(),
                  ))
              .toList(),
        ),
    };
  }

  @override
  Future<Result<List<AttendanceModel>>> getGroupAttendance({
    required String groupId,
    required String organizationId,
    required DateTime date,
  }) async {
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

  @override
  Future<Result<AttendanceModel>> markAttendance({
    required AttendanceModel record,
  }) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/attendance',
      body: _markBody(record),
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(_mergeMarkResponse(record, value)),
    };
  }

  @override
  Future<Result<AttendanceModel>> adminOverride({
    required AttendanceModel record,
  }) async {
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
        // FR-PG parity (ATT-004 self-mark): group selections travel exactly
        // like the member mark path; the server validates them identically.
        if (record.selections != null)
          'selections': record.selections!.map((s) => s.toJson()).toList(),
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      // FR-OVR-001 (Module 33): a liability-increasing override is NOT applied
      // by the backend — it creates a member confirmation instead. Surface
      // that as a friendly failure so every call site reports it through its
      // normal message path (the record genuinely did not change).
      Ok(:final value) when value['requiresMemberConsent'] == true => Err(
          ValidationFailure(
            message: (value['message'] ??
                    'Member consent required — a confirmation request was sent to the member.')
                .toString(),
          ),
        ),
      Ok(:final value) => Ok(_mergeMarkResponse(record, value)),
    };
  }

  @override
  Future<Result<AttendanceModel>> updateAttendance({
    required AttendanceModel record,
  }) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/attendance/${record.id}',
      body: _markBody(record),
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(_mergeMarkResponse(record, value)),
    };
  }

  Future<Result<AttendanceSummary>> getGroupAttendanceSummary({
    required String organizationId,
    required String groupId,
    DateTime? from,
    DateTime? to,
  }) async {
    final start = from ?? DateTime.now().subtract(const Duration(days: 30));
    final end = to ?? DateTime.now();
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

  /// Member Billing V2 — group-wide billing aggregation (admin).
  Future<Result<BillingSummaryV2>> getBillingSummaryV2({
    required String organizationId,
    required String groupId,
    required DateTime from,
    required DateTime to,
  }) async {
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

  /// Issue 5 — the signed-in member's OWN net bill (meal + guest + ledger
  /// adjustments), from the SAME engine as the admin dashboard so both sides
  /// show one number. GET /attendance/my-billing.
  Future<Result<MyBilling>> getMyBilling({
    required String groupId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/attendance/my-billing',
      queryParameters: {
        'groupId': groupId,
        'fromDate': _dateOnly(from),
        'toDate': _dateOnly(to),
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(MyBilling.fromJson(value)),
    };
  }

  /// Member Billing analytics — bucketed revenue/present-meal time series.
  Future<Result<BillingSeries>> getBillingSeries({
    required String organizationId,
    required String groupId,
    required DateTime from,
    required DateTime to,
    required String bucket,
  }) async {
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

  /// Per-meal attendance + preference summary for a single date (admin).
  Future<Result<MealAttendanceSummary>> getMealAttendanceSummary({
    required String organizationId,
    required String mealId,
    DateTime? date,
  }) async {
    final day = date ?? DateTime.now();
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
}

import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// SRS FR-DISP-010 (Pass 7) — billing period finalization & controlled
/// reopen. A finalized period locks all attendance/billing writes for its
/// dates server-side (423 PERIOD_FINALIZED); reopening (reason mandatory,
/// audited) lifts the lock until re-finalized.
class BillingPeriodsRepository {
  BillingPeriodsRepository();

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// GET /billing/periods?groupId= — newest first.
  Future<Result<List<Map<String, dynamic>>>> list({
    required String groupId,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/billing/periods',
      queryParameters: {'groupId': groupId},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(
          (value['data'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(),
        ),
    };
  }

  /// POST /billing/periods — finalize (lock) [from, to] for the group.
  Future<Result<Map<String, dynamic>>> finalize({
    required String groupId,
    required DateTime from,
    required DateTime to,
  }) {
    return DioApiService.instance.post<Map<String, dynamic>>(
      '/billing/periods',
      body: {
        'groupId': groupId,
        'periodStart': _dateOnly(from),
        'periodEnd': _dateOnly(to),
      },
    );
  }

  /// POST /billing/periods/:id/reopen — controlled reopen, reason mandatory.
  Future<Result<Map<String, dynamic>>> reopen({
    required String periodId,
    required String reason,
  }) {
    return DioApiService.instance.post<Map<String, dynamic>>(
      '/billing/periods/$periodId/reopen',
      body: {'reason': reason},
    );
  }

  /// POST /billing/periods/:id/finalize — re-lock a reopened period.
  Future<Result<Map<String, dynamic>>> refinalize({required String periodId}) {
    return DioApiService.instance.post<Map<String, dynamic>>(
      '/billing/periods/$periodId/finalize',
      body: const {},
    );
  }
}

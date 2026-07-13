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

  // ── Pass 12 (FR-BILLX-030/031, LOOP-010) — append-only adjustments ─────────

  /// POST /billing/adjustments — immutable ledger entry. `type` is
  /// credit | refund (decrease, free) or debit (increase — server demands an
  /// APPROVED correction-request id as consent proof, FR-FAIR-001).
  Future<Result<Map<String, dynamic>>> createAdjustment({
    required String groupId,
    required String userId,
    required String type,
    required int amountPaise,
    required String reason,
    String? refRequestId,
    String? refRecordId,
  }) {
    return DioApiService.instance.post<Map<String, dynamic>>(
      '/billing/adjustments',
      body: {
        'groupId': groupId,
        'userId': userId,
        'type': type,
        'amount': amountPaise,
        'reason': reason,
        if (refRequestId != null && refRequestId.isNotEmpty)
          'refRequestId': refRequestId,
        if (refRecordId != null && refRecordId.isNotEmpty)
          'refRecordId': refRecordId,
      },
    );
  }

  /// GET /billing/adjustments/my-pending — the signed-in member's own debits
  /// awaiting THEIR approval (command_6 survey 2026-07-13: an admin-proposed
  /// charge only bills after the member approves it).
  Future<Result<List<Map<String, dynamic>>>> myPendingAdjustments() async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/billing/adjustments/my-pending',
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

  /// POST /billing/adjustments/:id/approve|reject — decide my pending debit.
  Future<Result<Map<String, dynamic>>> decideAdjustment({
    required String entryId,
    required bool approve,
  }) {
    return DioApiService.instance.post<Map<String, dynamic>>(
      '/billing/adjustments/$entryId/${approve ? 'approve' : 'reject'}',
      body: const {},
    );
  }

  /// GET /billing/adjustments — newest first, optional member filter.
  Future<Result<List<Map<String, dynamic>>>> listAdjustments({
    required String groupId,
    String? userId,
    int page = 1,
    int limit = 50,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/billing/adjustments',
      queryParameters: {
        'groupId': groupId,
        if (userId != null) 'userId': userId,
        'page': '$page',
        'limit': '$limit',
      },
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
}

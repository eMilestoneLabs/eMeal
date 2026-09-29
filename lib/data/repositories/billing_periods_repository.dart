import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
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

  /// Live-Test-16 ISSUE-16: EVERY ledger adjustment in [from]..[to] for an
  /// export — admin: GET /billing/adjustments (optional [userId]); member
  /// ([mine]): GET /billing/adjustments/mine (server forces the caller).
  /// Pages of 100 (the server's page cap) until a short page; a failed page
  /// fails the whole read — an export is never silently missing entries.
  Future<Result<List<Map<String, dynamic>>>> listAdjustmentsForExport({
    required String groupId,
    required DateTime from,
    required DateTime to,
    String? userId,
    bool mine = false,
  }) async {
    const pageSize = AppConstants.adjustmentExportPageSize;
    const maxPages = AppConstants.adjustmentExportMaxPages;
    final all = <Map<String, dynamic>>[];
    for (var page = 1; page <= maxPages; page++) {
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        mine ? '/billing/adjustments/mine' : '/billing/adjustments',
        queryParameters: {
          'groupId': groupId,
          if (!mine && userId != null) 'userId': userId,
          'fromDate': _dateOnly(from),
          'toDate': _dateOnly(to),
          'page': '$page',
          'limit': '$pageSize',
        },
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final rows = (value['data'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
          all.addAll(rows);
          final total = (value['total'] as num?)?.toInt();
          if (rows.length < pageSize || (total != null && all.length >= total)) {
            return Ok(all);
          }
      }
    }
    // Never hand a truncated ledger to an export.
    return const Err(UnexpectedFailure(
      message:
          'Too many entries. Choose a shorter range.',
    ));
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

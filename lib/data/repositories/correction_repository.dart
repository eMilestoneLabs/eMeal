import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/correction_request_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Module 33 — Attendance Correction Request data access (FR-ACR-*).
///
/// Talks to the additive `/attendance/correction-requests` API. Organisation +
/// requesting user are derived server-side from the JWT — never sent by the
/// client.
class CorrectionRepository {
  CorrectionRepository();

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Raise a correction request for a (meal, date) — FR-ACR-001.
  Future<Result<CorrectionRequestModel>> createRequest({
    required String mealId,
    required DateTime attendanceDate,
    required String requestType,
    String? requestedPreference,
    String? reason,
  }) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/attendance/correction-requests',
      body: {
        'mealId': mealId,
        'attendanceDate': _d(attendanceDate),
        'requestType': requestType,
        if (requestedPreference != null && requestedPreference.isNotEmpty)
          'requestedPreference': requestedPreference,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(CorrectionRequestModel.fromJson(value)),
    };
  }

  /// List requests. Admins receive the org/group queue; members receive only
  /// their own (enforced server-side from the JWT role).
  Future<Result<PaginatedResponse<CorrectionRequestModel>>> list({
    String? groupId,
    String? status,
    String? sourceChannel,
    int page = 1,
    int limit = 50,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/attendance/correction-requests',
      queryParameters: {
        if (groupId != null) 'groupId': groupId,
        if (status != null) 'status': status,
        if (sourceChannel != null) 'sourceChannel': sourceChannel,
        'page': '$page',
        'limit': '$limit',
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(
          PaginatedResponse.fromJson(value, CorrectionRequestModel.fromJson)),
    };
  }

  /// Admin approves — the requested change is applied and billed (FR-ACR-010).
  Future<Result<CorrectionRequestModel>> approve(String id, {String? note}) =>
      _action('$id/approve', note);

  /// Admin rejects — nothing changes (FR-ACR-010).
  Future<Result<CorrectionRequestModel>> reject(String id, {String? note}) =>
      _action('$id/reject', note);

  /// Member cancels their own pending request (FR-ACR-011).
  Future<Result<CorrectionRequestModel>> cancel(String id, {String? note}) =>
      _action('$id/cancel', note);

  /// Member CONFIRMS an admin-proposed increase (FR-OVR-020).
  Future<Result<CorrectionRequestModel>> confirm(String id) =>
      _action('$id/confirm', null);

  /// Member DECLINES an admin-proposed increase (FR-OVR-020).
  Future<Result<CorrectionRequestModel>> decline(String id, {String? note}) =>
      _action('$id/decline', note);

  Future<Result<CorrectionRequestModel>> _action(
      String path, String? note) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/attendance/correction-requests/$path',
      body: {if (note != null && note.isNotEmpty) 'note': note},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(CorrectionRequestModel.fromJson(value)),
    };
  }
}

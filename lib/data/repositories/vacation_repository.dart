import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';

/// Issue 3 — vacation approval workflow data access.
///
/// Talks to the additive `/vacation-requests` API. Organisation + requesting
/// user are derived server-side from the JWT — never sent by the client.
class VacationRepository {
  VacationRepository();

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Submit a vacation request (any member).
  Future<Result<VacationRequestModel>> createRequest({
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
    String? groupId,
  }) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/vacation-requests',
      body: {
        'startDate': _d(startDate),
        'endDate': _d(endDate),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (groupId != null) 'groupId': groupId,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(VacationRequestModel.fromJson(value)),
    };
  }

  /// List requests. Admins receive every request in the org; members receive
  /// only their own (enforced server-side from the JWT role).
  Future<Result<PaginatedResponse<VacationRequestModel>>> list({
    String? groupId,
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/vacation-requests',
      queryParameters: {
        if (groupId != null) 'groupId': groupId,
        if (status != null) 'status': status,
        'page': '$page',
        'limit': '$limit',
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(
          PaginatedResponse.fromJson(value, VacationRequestModel.fromJson)),
    };
  }

  Future<Result<VacationRequestModel>> approve(String id, {String? note}) =>
      _review('$id/approve', note);

  Future<Result<VacationRequestModel>> reject(String id, {String? note}) =>
      _review('$id/reject', note);

  Future<Result<VacationRequestModel>> cancel(String id, {String? note}) =>
      _review('$id/cancel', note);

  Future<Result<VacationRequestModel>> _review(
      String path, String? note) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/vacation-requests/$path',
      body: {if (note != null && note.isNotEmpty) 'note': note},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(VacationRequestModel.fromJson(value)),
    };
  }
}

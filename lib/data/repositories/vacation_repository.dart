import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';

/// Issue 3 — vacation approval workflow data access.
///
/// Talks to the additive `/vacation-requests` API. Organisation + requesting
/// user are derived server-side from the JWT — never sent by the client. In
/// mock mode it keeps a tiny in-memory store so the UI is usable offline.
class VacationRepository {
  VacationRepository();

  static bool get _isMock => EnvConfig.current.mockAuthEnabled;

  static final List<VacationRequestModel> _mockStore = [];

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
    if (!_isMock) {
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
    final now = DateTime.now();
    final req = VacationRequestModel(
      id: 'mock_${now.microsecondsSinceEpoch}',
      organizationId: 'mock_org',
      userId: 'mock_user',
      userName: 'You',
      groupId: groupId,
      startDate: startDate,
      endDate: endDate,
      reason: reason,
      status: 'pending',
      createdAt: now,
      updatedAt: now,
    );
    _mockStore.insert(0, req);
    return Ok(req);
  }

  /// List requests. Admins receive every request in the org; members receive
  /// only their own (enforced server-side from the JWT role).
  Future<Result<PaginatedResponse<VacationRequestModel>>> list({
    String? groupId,
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    if (!_isMock) {
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
    final data = _mockStore
        .where((r) => status == null || r.status == status)
        .toList();
    return Ok(PaginatedResponse(
      data: data,
      total: data.length,
      page: 1,
      limit: data.length + 1,
    ));
  }

  Future<Result<VacationRequestModel>> approve(String id,
      {String? note}) =>
      _review('$id/approve', note);

  Future<Result<VacationRequestModel>> reject(String id, {String? note}) =>
      _review('$id/reject', note);

  Future<Result<VacationRequestModel>> cancel(String id, {String? note}) =>
      _review('$id/cancel', note);

  Future<Result<VacationRequestModel>> _review(
      String path, String? note) async {
    if (!_isMock) {
      final result = await DioApiService.instance.patch<Map<String, dynamic>>(
        '/vacation-requests/$path',
        body: {if (note != null && note.isNotEmpty) 'note': note},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(VacationRequestModel.fromJson(value)),
      };
    }
    // Mock: derive id + action from the path and mutate the local store.
    final parts = path.split('/');
    final id = parts.first;
    final action = parts.last;
    final i = _mockStore.indexWhere((r) => r.id == id);
    if (i == -1) {
      return const Err(NetworkFailure(message: 'Not found', statusCode: 404));
    }
    final newStatus = switch (action) {
      'approve' => 'approved',
      'reject' => 'rejected',
      _ => 'cancelled',
    };
    final cur = _mockStore[i];
    final updated = VacationRequestModel(
      id: cur.id,
      organizationId: cur.organizationId,
      groupId: cur.groupId,
      userId: cur.userId,
      userName: cur.userName,
      startDate: cur.startDate,
      endDate: cur.endDate,
      reason: cur.reason,
      status: newStatus,
      reviewedAt: DateTime.now(),
      reviewNote: note,
      createdAt: cur.createdAt,
      updatedAt: DateTime.now(),
    );
    _mockStore[i] = updated;
    return Ok(updated);
  }
}

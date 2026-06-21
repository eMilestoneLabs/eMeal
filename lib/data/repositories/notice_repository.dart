import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/notice_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Notice board data access (Phase B). Talks to the additive `/notices` API.
///
/// Organisation scope is derived server-side from the JWT — never sent by the
/// client. In mock mode it keeps a tiny in-memory store so the UI is usable
/// without a backend.
class NoticeRepository {
  NoticeRepository();

  static bool get _isMock => EnvConfig.current.mockAuthEnabled;

  // In-memory mock store (only used when mockAuthEnabled = true).
  static final List<NoticeModel> _mockStore = [];

  Future<Result<PaginatedResponse<NoticeModel>>> getNotices({
    required String organizationId,
    String? groupId,
    int page = 1,
    int limit = 20,
    bool includeInactive = false,
  }) async {
    if (!_isMock) {
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/notices',
        queryParameters: {
          if (groupId != null) 'groupId': groupId,
          'page': '$page',
          'limit': '$limit',
          if (includeInactive) 'includeInactive': 'true',
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          Ok(PaginatedResponse.fromJson(value, NoticeModel.fromJson)),
      };
    }
    final data = List<NoticeModel>.from(_mockStore);
    return Ok(PaginatedResponse(
      data: data,
      total: data.length,
      page: 1,
      limit: data.length + 1,
    ));
  }

  Future<Result<int>> getUnreadCount({
    required String organizationId,
    String? groupId,
  }) async {
    if (!_isMock) {
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/notices/unread-count',
        queryParameters: {if (groupId != null) 'groupId': groupId},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok((value['count'] as num?)?.toInt() ?? 0),
      };
    }
    return Ok(_mockStore.where((n) => !n.isRead).length);
  }

  Future<Result<Unit>> markRead(String noticeId) async {
    if (!_isMock) {
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/notices/$noticeId/read',
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
    }
    final i = _mockStore.indexWhere((n) => n.id == noticeId);
    if (i != -1) _mockStore[i] = _mockStore[i].copyWith(isRead: true);
    return const Ok(Unit.instance);
  }

  Future<Result<int>> markAllRead({String? groupId}) async {
    if (!_isMock) {
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/notices/read-all',
        body: {if (groupId != null) 'groupId': groupId},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok((value['updated'] as num?)?.toInt() ?? 0),
      };
    }
    var n = 0;
    for (var i = 0; i < _mockStore.length; i++) {
      if (!_mockStore[i].isRead) {
        _mockStore[i] = _mockStore[i].copyWith(isRead: true);
        n++;
      }
    }
    return Ok(n);
  }

  Future<Result<NoticeModel>> createNotice({
    required String title,
    required String body,
    String? groupId,
    String priority = 'normal',
    bool pinned = false,
    DateTime? expiresAt,
  }) async {
    if (!_isMock) {
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/notices',
        body: {
          'title': title,
          'body': body,
          if (groupId != null) 'groupId': groupId,
          'priority': priority,
          'pinned': pinned,
          if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(NoticeModel.fromJson(value)),
      };
    }
    final now = DateTime.now();
    final notice = NoticeModel(
      id: 'mock_${now.microsecondsSinceEpoch}',
      organizationId: 'mock_org',
      groupId: groupId,
      createdBy: 'mock_admin',
      title: title,
      body: body,
      priority: priority,
      pinned: pinned,
      isActive: true,
      isRead: false,
      readCount: 0,
      publishedAt: now,
      expiresAt: expiresAt,
      createdAt: now,
      updatedAt: now,
    );
    _mockStore.insert(0, notice);
    return Ok(notice);
  }

  Future<Result<Unit>> deleteNotice(String noticeId) async {
    if (!_isMock) {
      final result = await DioApiService.instance.delete<Map<String, dynamic>>(
        '/notices/$noticeId',
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
    }
    _mockStore.removeWhere((n) => n.id == noticeId);
    return const Ok(Unit.instance);
  }
}

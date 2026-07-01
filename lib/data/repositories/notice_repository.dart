import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/notice_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Notice board data access (Phase B). Talks to the additive `/notices` API.
///
/// Organisation scope is derived server-side from the JWT — never sent by the
/// client.
class NoticeRepository {
  NoticeRepository();

  Future<Result<PaginatedResponse<NoticeModel>>> getNotices({
    required String organizationId,
    String? groupId,
    int page = 1,
    int limit = 20,
    bool includeInactive = false,
  }) async {
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

  Future<Result<int>> getUnreadCount({
    required String organizationId,
    String? groupId,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/notices/unread-count',
      queryParameters: {if (groupId != null) 'groupId': groupId},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok((value['count'] as num?)?.toInt() ?? 0),
    };
  }

  Future<Result<Unit>> markRead(String noticeId) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/notices/$noticeId/read',
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  Future<Result<int>> markAllRead({String? groupId}) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/notices/read-all',
      body: {if (groupId != null) 'groupId': groupId},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok((value['updated'] as num?)?.toInt() ?? 0),
    };
  }

  Future<Result<NoticeModel>> createNotice({
    required String title,
    required String body,
    String? groupId,
    String priority = 'normal',
    bool pinned = false,
    DateTime? expiresAt,
  }) async {
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

  Future<Result<Unit>> deleteNotice(String noticeId) async {
    final result = await DioApiService.instance.delete<Map<String, dynamic>>(
      '/notices/$noticeId',
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }
}

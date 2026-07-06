import 'package:smart_meal_management/data/contracts/i_group_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

/// Group repository — calls the live NestJS backend through [DioApiService].
///
/// Organisation scope is derived server-side from the JWT (never sent by the
/// client). Member records carry a nested `user` profile (additive contract),
/// mapped to [UserModel] by [_memberToUser].
class GroupRepository implements IGroupRepository {
  GroupRepository();

  @override
  Future<Result<PaginatedResponse<GroupModel>>> getOrganisationGroups({
    required String organizationId,
    bool includeInactive = false,
  }) async {
    // GET /groups — org scope comes from the JWT, never the client.
    // GRP-016/018: includeInactive surfaces archived groups (admin only) so
    // they can be restored or permanently deleted.
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/groups',
      queryParameters: {
        'page': '1',
        'limit': '100',
        if (includeInactive) 'includeInactive': 'true',
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) =>
        Ok(PaginatedResponse.fromJson(value, GroupModel.fromJson)),
    };
  }

  @override
  Future<Result<List<GroupModel>>> getUserGroups({
    required String userId,
    required String organizationId,
  }) async {
    // GET /groups then filter to the user's memberships using the
    // serializer-provided memberIds[] (group serializer contract).
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/groups',
      queryParameters: {'page': '1', 'limit': '100'},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(
          PaginatedResponse.fromJson(value, GroupModel.fromJson)
              .data
              .where((g) =>
                  g.isActive &&
                  (g.memberIds.contains(userId) || g.adminId == userId))
              .toList(),
        ),
    };
  }

  @override
  Future<Result<GroupModel>> getGroup({
    required String organizationId,
    required String groupId,
  }) async {
    final result = await DioApiService.instance
        .get<Map<String, dynamic>>('/groups/$groupId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(GroupModel.fromJson(value)),
    };
  }

  @override
  Future<Result<GroupModel>> createGroup({
    required String organizationId,
    required String name,
    required GroupType type,
    String? description,
    int? maxMembers,
    GroupMealConfig? mealConfig,
    UserRole? functionalRole,
    // Module 02 (GRP-003) — extended metadata + policy captured at creation.
    String? country,
    String? state,
    String? city,
    String? pin,
    String? address,
    String? timezone,
    String? currency,
    bool? joinApprovalRequired,
    int? qrExpiryDays,
  }) async {
    // POST /groups — CreateGroupDto whitelist only.
    // type.name serializes factory_ as "factory_" (locked API contract).
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/groups',
      body: {
        'name': name,
        'type': type.name,
        if (description != null) 'description': description,
        if (maxMembers != null) 'maxMembers': maxMembers,
        if (mealConfig != null) 'mealConfig': mealConfig.toJson(),
        if (functionalRole != null) 'functionalRole': functionalRole.name,
        // Module 02 additive fields — only sent when provided.
        if (country != null) 'country': country,
        if (state != null) 'state': state,
        if (city != null) 'city': city,
        if (pin != null) 'pin': pin,
        if (address != null) 'address': address,
        if (timezone != null) 'timezone': timezone,
        if (currency != null) 'currency': currency,
        if (joinApprovalRequired != null)
          'joinApprovalRequired': joinApprovalRequired,
        if (qrExpiryDays != null) 'qrExpiryDays': qrExpiryDays,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(GroupModel.fromJson(value)),
    };
  }

  @override
  Future<Result<GroupModel>> updateGroup({
    required String organizationId,
    required String groupId,
    String? name,
    GroupType? type,
    String? description,
    GroupMealConfig? mealConfig,
    int? maxMembers,
    UserRole? functionalRole,
  }) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/groups/$groupId',
      body: {
        if (name != null) 'name': name,
        if (type != null) 'type': type.name,
        if (description != null) 'description': description,
        if (maxMembers != null) 'maxMembers': maxMembers,
        if (mealConfig != null) 'mealConfig': mealConfig.toJson(),
        if (functionalRole != null) 'functionalRole': functionalRole.name,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(GroupModel.fromJson(value)),
    };
  }

  @override
  Future<Result<Unit>> archiveGroup({
    required String organizationId,
    required String groupId,
  }) async {
    // DELETE /groups/:id — soft-delete (archive) server-side.
    final result =
        await DioApiService.instance.delete<dynamic>('/groups/$groupId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  @override
  Future<Result<PaginatedResponse<UserModel>>> getGroupMembers({
    required String organizationId,
    required String groupId,
  }) async {
    // GET /groups/:id/members — paginated member records.
    // Each record carries a nested `user` profile (additive contract).
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/groups/$groupId/members',
      queryParameters: {'page': '1', 'limit': '100'},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) =>
        Ok(PaginatedResponse.fromJson(value, _memberToUser)),
    };
  }

  @override
  Future<Result<Unit>> removeMember({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    // DELETE /groups/:id/members/:userId — :memberId == userId.
    final result = await DioApiService.instance
        .delete<dynamic>('/groups/$groupId/members/$userId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  @override
  Future<Result<GroupModel>> joinGroup({
    required String organizationId,
    required String joinCode,
    required String userId,
    String? functionalRole,
  }) async {
    // POST /groups/join — org scope derives from the JWT.
    // Blocked / already-member rules enforced server-side.
    // #2: functionalRole is the member's chosen per-group display title
    // (member-level only; validated + gated server-side). Omitted when null.
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/groups/join',
      body: {
        'joinCode': joinCode,
        if (functionalRole != null) 'functionalRole': functionalRole,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(GroupModel.fromJson(value)),
    };
  }

  @override
  Future<Result<Unit>> blockMember({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    // PATCH /groups/:id/members/:userId { status: 'blocked' }.
    final result = await DioApiService.instance.patch<dynamic>(
      '/groups/$groupId/members/$userId',
      body: {'status': 'blocked'},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  @override
  Future<Result<Unit>> unblockMember({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    // PATCH /groups/:id/members/:userId/unblock — restores active.
    final result = await DioApiService.instance
        .patch<dynamic>('/groups/$groupId/members/$userId/unblock');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  // ── Live member mapping ────────────────────────────────────────────────────

  /// Maps a backend group-member record to a [UserModel].
  /// Member records nest the joined profile under `user`; fall back to a
  /// minimal model built from membership fields when it is absent.
  UserModel _memberToUser(Map<String, dynamic> m) {
    // #2: the per-group display role lives on the OUTER membership record
    // (m['functionalRole']), not the nested account profile. Carry it onto the
    // UserModel WITHOUT touching [role] so admin gating (isAdmin) is unchanged.
    final groupRole = UserRole.fromName(m['functionalRole'] as String?);
    final user = m['user'];
    if (user is Map<String, dynamic>) {
      return UserModel.fromJson(user)
          .copyWith(groupFunctionalRole: groupRole ?? UserModel.absent);
    }
    final status = m['status'];
    return UserModel(
      id: (m['userId'] ?? '').toString(),
      name: '',
      email: '',
      role: UserRole.student,
      organizationId: '',
      isActive: status != 'blocked' && status != 'removed',
      groupFunctionalRole: groupRole,
    );
  }

  // ── Convenience aliases used by GroupProvider ──────────────────────────────

  /// Alias: loads groups for [userId] within [organizationId].
  Future<Result<List<GroupModel>>> getMyGroups(
    String userId, {
    required String organizationId,
  }) =>
      getUserGroups(userId: userId, organizationId: organizationId);

  /// Alias: loads a single group by id.
  Future<Result<GroupModel>> getGroupById({
    required String organizationId,
    required String groupId,
  }) =>
      getGroup(organizationId: organizationId, groupId: groupId);

  /// Alias: joins a group by code within [organizationId].
  Future<Result<GroupModel>> joinGroupByCode({
    required String userId,
    required String joinCode,
    required String organizationId,
    String? functionalRole,
  }) =>
      joinGroup(
        organizationId: organizationId,
        joinCode: joinCode,
        userId: userId,
        functionalRole: functionalRole,
      );

  // ── Module 02 (Organization & Group Management) ─────────────────────────────

  /// GET /groups/limits — config-driven group + member limits so the UI can
  /// disable Create at the cap and bound the Maximum-Members input.
  Future<Result<Map<String, dynamic>>> getGroupLimits() async {
    final result =
        await DioApiService.instance.get<Map<String, dynamic>>('/groups/limits');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(value),
    };
  }

  /// GET /groups/preview?joinCode= — MEM-002 pre-join preview (identity +
  /// capacity + approval), no membership change.
  Future<Result<Map<String, dynamic>>> previewJoin({
    required String joinCode,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/groups/preview',
      queryParameters: {'joinCode': joinCode},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(value),
    };
  }

  /// POST /groups/:id/leave — MEM-016/017 self-service leave.
  Future<Result<Unit>> leaveGroup({required String groupId}) async {
    final result =
        await DioApiService.instance.post<dynamic>('/groups/$groupId/leave');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  /// GET /groups/my-join-requests — MEM-004/005 (Issue 4): the current user's
  /// own pending join requests, so the "Waiting for approval" state can be
  /// re-opened and cancelled after the inline flow is dismissed.
  Future<Result<List<GroupModel>>> getMyJoinRequests() async {
    final result = await DioApiService.instance
        .get<Map<String, dynamic>>('/groups/my-join-requests');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(
          ((value['data'] as List?) ?? [])
              .map((e) => GroupModel.fromJson((e as Map).cast<String, dynamic>()))
              .toList(),
        ),
    };
  }

  /// DELETE /groups/:id/join-request — MEM-005 cancel my own pending request.
  Future<Result<Unit>> cancelJoinRequest({required String groupId}) async {
    final result = await DioApiService.instance
        .delete<dynamic>('/groups/$groupId/join-request');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  /// POST /groups/:id/restore — GRP-018 restore an archived group (admin).
  Future<Result<GroupModel>> restoreGroup({required String groupId}) async {
    final result = await DioApiService.instance
        .post<Map<String, dynamic>>('/groups/$groupId/restore');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(GroupModel.fromJson(value)),
    };
  }

  /// DELETE /groups/:id/permanent — GRP-019 irreversible hard delete (admin).
  Future<Result<Unit>> permanentDeleteGroup({required String groupId}) async {
    final result = await DioApiService.instance
        .delete<dynamic>('/groups/$groupId/permanent');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  /// GET /groups/:id/join-requests — MEM-006 pending requests (admin).
  Future<Result<PaginatedResponse<UserModel>>> getJoinRequests({
    required String groupId,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/groups/$groupId/join-requests',
      queryParameters: {'page': '1', 'limit': '100'},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(PaginatedResponse.fromJson(value, _memberToUser)),
    };
  }

  /// PATCH /groups/:id/join-requests/:userId/approve — MEM-006 (admin).
  Future<Result<Unit>> approveJoinRequest({
    required String groupId,
    required String userId,
  }) async {
    final result = await DioApiService.instance
        .patch<dynamic>('/groups/$groupId/join-requests/$userId/approve');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  /// PATCH /groups/:id/join-requests/:userId/reject — MEM-007 (admin).
  Future<Result<Unit>> rejectJoinRequest({
    required String groupId,
    required String userId,
    String? reason,
  }) async {
    final result = await DioApiService.instance.patch<dynamic>(
      '/groups/$groupId/join-requests/$userId/reject',
      body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }
}

import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_group_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/data/mock/mock_groups_data.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

/// In-memory mock implementation of [IGroupRepository].
///
/// Pre-populated with [MockGroupsData]. Simulates 300 ms latency.
///
/// [_store] is static so that all repository instances (admin and student)
/// share the same in-memory data during an app session. This allows admin
/// block/unblock actions to be visible to the student join flow immediately.
class GroupRepository implements IGroupRepository {
  GroupRepository() {
    if (_isMock && !_initialized) {
      _store.addAll(MockGroupsData.groups());
      _initialized = true;
    }
  }

  /// B10: live/mock dispatch — same single switch as AuthRepository.
  static bool get _isMock => EnvConfig.current.mockAuthEnabled;

  // Shared in-memory store — survives across repository instances.
  static final List<GroupModel> _store = [];
  static bool _initialized = false;
  static int _idCounter = 100;

  static Future<void> _delay() =>
      Future.delayed(const Duration(milliseconds: 300));

  @override
  Future<Result<PaginatedResponse<GroupModel>>> getOrganisationGroups({
    required String organizationId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: GET /groups — org scope comes from the JWT, never the client.
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/groups',
        queryParameters: {'page': '1', 'limit': '100'},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          Ok(PaginatedResponse.fromJson(value, GroupModel.fromJson)),
      };
    }
    await _delay();
    final groups = _store
        .where((g) => g.organizationId == organizationId && g.isActive)
        .toList();
    return Ok(PaginatedResponse(
      data: groups,
      total: groups.length,
      page: 1,
      limit: groups.length + 1,
    ));
  }

  @override
  Future<Result<List<GroupModel>>> getUserGroups({
    required String userId,
    required String organizationId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: GET /groups then filter to the user's memberships using the
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
    await _delay();
    final groups = _store
        .where((g) =>
            g.organizationId == organizationId &&
            (g.memberIds.contains(userId) || g.adminId == userId) &&
            g.isActive)
        .toList();
    return Ok(groups);
  }

  @override
  Future<Result<GroupModel>> getGroup({
    required String organizationId,
    required String groupId,
  }) async {
    if (!_isMock) {
      final result = await DioApiService.instance
          .get<Map<String, dynamic>>('/groups/$groupId');
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(GroupModel.fromJson(value)),
      };
    }
    await _delay();
    try {
      final group = _store.firstWhere(
        (g) => g.id == groupId && g.organizationId == organizationId,
      );
      return Ok(group);
    } catch (_) {
      return const Err(NetworkFailure(message: 'Group not found.', statusCode: 404));
    }
  }

  @override
  Future<Result<GroupModel>> createGroup({
    required String organizationId,
    required String name,
    required GroupType type,
    String? description,
    int? maxMembers,
    GroupMealConfig? mealConfig,
  }) async {
    if (!_isMock) {
      // B10 LIVE: POST /groups — CreateGroupDto whitelist only.
      // type.name serializes factory_ as "factory_" (locked API contract).
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/groups',
        body: {
          'name': name,
          'type': type.name,
          if (description != null) 'description': description,
          if (maxMembers != null) 'maxMembers': maxMembers,
          if (mealConfig != null) 'mealConfig': mealConfig.toJson(),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(GroupModel.fromJson(value)),
      };
    }
    await _delay();
    final group = GroupModel(
      id: 'grp_${++_idCounter}',
      organizationId: organizationId,
      name: name,
      type: type,
      mealConfig: mealConfig ?? const GroupMealConfig(),
      memberIds: const [],
      description: description,
      maxMembers: maxMembers,
      isActive: true,
      joinCode: 'JOIN-$_idCounter',
      createdAt: DateTime.now(),
    );
    _store.add(group);
    return Ok(group);
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
  }) async {
    if (!_isMock) {
      final result = await DioApiService.instance.patch<Map<String, dynamic>>(
        '/groups/$groupId',
        body: {
          if (name != null) 'name': name,
          if (type != null) 'type': type.name,
          if (description != null) 'description': description,
          if (maxMembers != null) 'maxMembers': maxMembers,
          if (mealConfig != null) 'mealConfig': mealConfig.toJson(),
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(GroupModel.fromJson(value)),
      };
    }
    await _delay();
    final idx = _store.indexWhere((g) => g.id == groupId);
    if (idx == -1) {
      return const Err(NetworkFailure(message: 'Group not found.', statusCode: 404));
    }
    final updated = _store[idx].copyWith(
      name: name,
      type: type,
      description: description,
      mealConfig: mealConfig,
      maxMembers: maxMembers,
    );
    _store[idx] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<Unit>> archiveGroup({
    required String organizationId,
    required String groupId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: DELETE /groups/:id — soft-delete (archive) server-side.
      final result =
          await DioApiService.instance.delete<dynamic>('/groups/$groupId');
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
    }
    await _delay();
    final idx = _store.indexWhere((g) => g.id == groupId);
    if (idx == -1) {
      return const Err(NetworkFailure(message: 'Group not found.', statusCode: 404));
    }
    _store[idx] = _store[idx].copyWith(isActive: false);
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<PaginatedResponse<UserModel>>> getGroupMembers({
    required String organizationId,
    required String groupId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: GET /groups/:id/members — paginated member records.
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
    await _delay();
    final members = MockGroupsData.membersForGroup(groupId);
    return Ok(PaginatedResponse(
      data: members,
      total: members.length,
      page: 1,
      limit: members.length + 1,
    ));
  }

  @override
  Future<Result<Unit>> removeMember({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: DELETE /groups/:id/members/:userId — :memberId == userId.
      final result = await DioApiService.instance
          .delete<dynamic>('/groups/$groupId/members/$userId');
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
    }
    await _delay();
    final idx = _store.indexWhere((g) => g.id == groupId);
    if (idx == -1) {
      return const Err(NetworkFailure(message: 'Group not found.', statusCode: 404));
    }
    final group = _store[idx];
    _store[idx] = group.copyWith(
      memberIds: group.memberIds.where((id) => id != userId).toList(),
    );
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<GroupModel>> joinGroup({
    required String organizationId,
    required String joinCode,
    required String userId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: POST /groups/join — org scope derives from the JWT.
      // Blocked / already-member rules enforced server-side.
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/groups/join',
        body: {'joinCode': joinCode},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(GroupModel.fromJson(value)),
      };
    }
    await _delay();
    try {
      final idx = _store.indexWhere(
        (g) => g.joinCode == joinCode && g.organizationId == organizationId,
      );
      if (idx == -1) {
        return const Err(ValidationFailure(message: 'Invalid join code. Please check with your admin.'));
      }
      final group = _store[idx];

      // Blocked user check — must come before already-member check
      if (group.blockedMemberIds.contains(userId)) {
        return const Err(ValidationFailure(
          message: 'You have been blocked from joining this group. '
              'Please contact your admin for help.',
        ));
      }

      // Idempotent: already a member
      if (group.memberIds.contains(userId)) {
        return const Err(ValidationFailure(
          message: 'You are already a member of this group.',
        ));
      }

      final updated = group.copyWith(
        memberIds: [...group.memberIds, userId],
      );
      _store[idx] = updated;
      return Ok(updated);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to join group: $e'));
    }
  }

  @override
  Future<Result<Unit>> blockMember({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: PATCH /groups/:id/members/:userId { status: 'blocked' }.
      final result = await DioApiService.instance.patch<dynamic>(
        '/groups/$groupId/members/$userId',
        body: {'status': 'blocked'},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
    }
    await _delay();
    final idx = _store.indexWhere((g) => g.id == groupId);
    if (idx == -1) {
      return const Err(NetworkFailure(message: 'Group not found.', statusCode: 404));
    }
    final group = _store[idx];
    if (!group.blockedMemberIds.contains(userId)) {
      _store[idx] = group.copyWith(
        blockedMemberIds: [...group.blockedMemberIds, userId],
        // Also remove from active members when blocked
        memberIds: group.memberIds.where((id) => id != userId).toList(),
      );
    }
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<Unit>> unblockMember({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: PATCH /groups/:id/members/:userId/unblock — restores active.
      final result = await DioApiService.instance
          .patch<dynamic>('/groups/$groupId/members/$userId/unblock');
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
    }
    await _delay();
    final idx = _store.indexWhere((g) => g.id == groupId);
    if (idx == -1) {
      return const Err(NetworkFailure(message: 'Group not found.', statusCode: 404));
    }
    final group = _store[idx];
    _store[idx] = group.copyWith(
      blockedMemberIds: group.blockedMemberIds.where((id) => id != userId).toList(),
    );
    return const Ok(Unit.instance);
  }

  // ── Live member mapping ────────────────────────────────────────────────────

  /// Maps a backend group-member record to a [UserModel].
  /// Member records nest the joined profile under `user`; fall back to a
  /// minimal model built from membership fields when it is absent.
  UserModel _memberToUser(Map<String, dynamic> m) {
    final user = m['user'];
    if (user is Map<String, dynamic>) {
      return UserModel.fromJson(user);
    }
    final status = m['status'];
    return UserModel(
      id: (m['userId'] ?? '').toString(),
      name: '',
      email: '',
      role: UserRole.student,
      organizationId: '',
      isActive: status != 'blocked' && status != 'removed',
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
  }) =>
      joinGroup(
        organizationId: organizationId,
        joinCode: joinCode,
        userId: userId,
      );

}

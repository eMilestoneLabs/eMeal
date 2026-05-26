import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_group_repository.dart';
import 'package:smart_meal_management/data/mock/mock_groups_data.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// In-memory mock implementation of [IGroupRepository].
///
/// Pre-populated with [MockGroupsData]. Simulates 300 ms latency.
///
/// [_store] is static so that all repository instances (admin and student)
/// share the same in-memory data during an app session. This allows admin
/// block/unblock actions to be visible to the student join flow immediately.
class GroupRepository implements IGroupRepository {
  GroupRepository() {
    if (!_initialized) {
      _store.addAll(MockGroupsData.groups());
      _initialized = true;
    }
  }

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

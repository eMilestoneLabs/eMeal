import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Abstract contract for group management operations.
abstract interface class IGroupRepository {
  /// Fetch all groups belonging to [organizationId].
  Future<Result<PaginatedResponse<GroupModel>>> getOrganisationGroups({
    required String organizationId,
  });

  /// Fetch all groups that [userId] belongs to.
  Future<Result<List<GroupModel>>> getUserGroups({
    required String userId,
    required String organizationId,
  });

  /// Fetch a single group by ID.
  Future<Result<GroupModel>> getGroup({
    required String organizationId,
    required String groupId,
  });

  /// Create a new group.
  Future<Result<GroupModel>> createGroup({
    required String organizationId,
    required String name,
    required GroupType type,
    String? description,
    int? maxMembers,
    GroupMealConfig? mealConfig,
  });

  /// Update group metadata / meal config.
  Future<Result<GroupModel>> updateGroup({
    required String organizationId,
    required String groupId,
    String? name,
    GroupType? type,
    String? description,
    GroupMealConfig? mealConfig,
    int? maxMembers,
  });

  /// Soft-archive a group (sets isActive = false).
  Future<Result<Unit>> archiveGroup({
    required String organizationId,
    required String groupId,
  });

  /// Fetch paginated member list for a group.
  Future<Result<PaginatedResponse<UserModel>>> getGroupMembers({
    required String organizationId,
    required String groupId,
  });

  /// Remove a member from a group.
  Future<Result<Unit>> removeMember({
    required String organizationId,
    required String groupId,
    required String userId,
  });

  /// Block a member from attending or rejoining the group.
  Future<Result<Unit>> blockMember({
    required String organizationId,
    required String groupId,
    required String userId,
  });

  /// Unblock a previously blocked member.
  Future<Result<Unit>> unblockMember({
    required String organizationId,
    required String groupId,
    required String userId,
  });

  /// Join a group using an invite / join code.
  ///
  /// Returns [Err] with a [ValidationFailure] if:
  /// - The join code is invalid / not found.
  /// - The user is blocked from this group.
  /// Returns [Ok] with the group if already a member (idempotent).
  Future<Result<GroupModel>> joinGroup({
    required String organizationId,
    required String joinCode,
    required String userId,
  });
}

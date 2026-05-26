import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// State manager for admin group management.
///
/// Repository-driven architecture using [GroupRepository] + [MealRepository].
/// Supports full CRUD lifecycle with optimistic UI updates.
/// Loads meals dynamically for the selected group (no hardcoded meal types).
class AdminGroupProvider extends ChangeNotifier {
  AdminGroupProvider({GroupRepository? groupRepo, MealRepository? mealRepo})
      : _groupRepo = groupRepo ?? GroupRepository(),
        _mealRepo = mealRepo ?? MealRepository();

  final GroupRepository _groupRepo;
  final MealRepository _mealRepo;

  // ── State ─────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool _isCreating = false;
  bool _isLoadingMembers = false;
  bool _isLoadingMeals = false;
  String? _error;

  List<GroupModel> _groups = [];
  GroupModel? _selectedGroup;
  List<UserModel> _selectedGroupMembers = [];

  /// Meals configured for [_selectedGroup]. Empty until [loadGroupMeals] runs.
  /// Populated dynamically — never hardcoded to any fixed meal types.
  List<MealModel> _selectedGroupMeals = [];

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  bool get isCreating => _isCreating;
  bool get isLoadingMembers => _isLoadingMembers;
  bool get isLoadingMeals => _isLoadingMeals;
  String? get error => _error;
  List<GroupModel> get groups => _groups;
  GroupModel? get selectedGroup => _selectedGroup;
  List<UserModel> get selectedGroupMembers => _selectedGroupMembers;

  /// Dynamic meal list for the selected group.
  List<MealModel> get selectedGroupMeals => _selectedGroupMeals;

  int get totalMembers => _groups.fold(0, (s, g) => s + g.memberCount);
  int get activeGroupCount => _groups.where((g) => g.isActive).length;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> loadGroups({required String organizationId}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _groupRepo.getOrganisationGroups(
      organizationId: organizationId,
    );

    switch (result) {
      case Ok(:final value):
        _groups = value.data;
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectGroup({
    required String groupId,
    required String organizationId,
  }) async {
    try {
      _selectedGroup = _groups.firstWhere((g) => g.id == groupId);
    } catch (_) {
      // Group not in list yet, will be loaded
    }
    // Clear stale meal/member lists immediately so UI shows loading state
    _selectedGroupMeals = [];
    _selectedGroupMembers = [];
    notifyListeners();
    // Load members and meals in parallel
    await Future.wait([
      loadGroupMembers(groupId: groupId, organizationId: organizationId),
      loadGroupMeals(groupId: groupId, organizationId: organizationId),
    ]);
  }

  /// Loads the dynamically configured meals for a group.
  ///
  /// Results are stored in [selectedGroupMeals] and used by the Meals tab in
  /// [AdminGroupDetailScreen] — fully dynamic, never hardcoded to fixed types.
  Future<void> loadGroupMeals({
    required String groupId,
    required String organizationId,
  }) async {
    _isLoadingMeals = true;
    notifyListeners();

    final result = await _mealRepo.getGroupMeals(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok(:final value):
        _selectedGroupMeals = value;
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoadingMeals = false;
    notifyListeners();
  }

  Future<void> loadGroupMembers({
    required String groupId,
    required String organizationId,
  }) async {
    _isLoadingMembers = true;
    notifyListeners();

    final result = await _groupRepo.getGroupMembers(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok(:final value):
        _selectedGroupMembers = value.data;
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoadingMembers = false;
    notifyListeners();
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<GroupModel?> createGroup({
    required String organizationId,
    required String name,
    required GroupType type,
    String? description,
    int? maxMembers,
    GroupMealConfig? mealConfig,
  }) async {
    _isCreating = true;
    _error = null;
    notifyListeners();

    final result = await _groupRepo.createGroup(
      organizationId: organizationId,
      name: name,
      type: type,
      description: description,
      maxMembers: maxMembers,
      mealConfig: mealConfig,
    );

    switch (result) {
      case Ok(:final value):
        _groups = [value, ..._groups];
        _isCreating = false;
        notifyListeners();
        return value;
      case Err(:final failure):
        _error = failure.message;
        _isCreating = false;
        notifyListeners();
        return null;
    }
  }

  Future<bool> updateGroup({
    required String organizationId,
    required String groupId,
    String? name,
    GroupType? type,
    String? description,
    GroupMealConfig? mealConfig,
    int? maxMembers,
  }) async {
    final result = await _groupRepo.updateGroup(
      organizationId: organizationId,
      groupId: groupId,
      name: name,
      type: type,
      description: description,
      mealConfig: mealConfig,
      maxMembers: maxMembers,
    );

    switch (result) {
      case Ok(:final value):
        final idx = _groups.indexWhere((g) => g.id == groupId);
        if (idx != -1) {
          _groups = List.of(_groups)..[idx] = value;
        }
        if (_selectedGroup?.id == groupId) _selectedGroup = value;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  Future<bool> archiveGroup(
    String groupId, {
    required String organizationId,
  }) async {
    final result = await _groupRepo.archiveGroup(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok():
        final idx = _groups.indexWhere((g) => g.id == groupId);
        if (idx != -1) {
          _groups = List.of(_groups)
            ..[idx] = _groups[idx].copyWith(isActive: false);
        }
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── Membership ────────────────────────────────────────────────────────────

  Future<bool> removeMember({
    required String groupId,
    required String userId,
    required String organizationId,
  }) async {
    final result = await _groupRepo.removeMember(
      organizationId: organizationId,
      groupId: groupId,
      userId: userId,
    );

    switch (result) {
      case Ok():
        // Optimistic update: remove from group memberIds
        final idx = _groups.indexWhere((g) => g.id == groupId);
        if (idx != -1) {
          final g = _groups[idx];
          _groups = List.of(_groups)
            ..[idx] = g.copyWith(
              memberIds: g.memberIds.where((id) => id != userId).toList(),
            );
        }
        // Remove from members list
        _selectedGroupMembers =
            _selectedGroupMembers.where((m) => m.id != userId).toList();
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── QR regeneration ────────────────────────────────────────────────────────

  Future<bool> regenerateQR(String groupId) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return false;

    // Generate a new 6-char alphanumeric join code
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = DateTime.now().millisecondsSinceEpoch;
    final newCode = List.generate(6, (i) => chars[(rand >> i) % chars.length])
        .join();

    _groups = List.of(_groups)
      ..[idx] = _groups[idx].copyWith(joinCode: newCode);
    if (_selectedGroup?.id == groupId) {
      _selectedGroup = _groups[idx];
    }
    notifyListeners();
    return true;
  }

  // ── Block / Unblock ───────────────────────────────────────────────────────

  /// Local cache of blocked user IDs for fast UI checks.
  ///
  /// Kept in sync with [GroupRepository._store] via [blockMember] /
  /// [unblockMember]. Because the repository store is static, the student
  /// join flow will see the blocked state immediately in the same session.
  final Set<String> _blockedIds = {};

  Set<String> get blockedIds => Set.unmodifiable(_blockedIds);

  bool isMemberBlocked(String userId) => _blockedIds.contains(userId);

  Future<bool> blockMember({
    required String groupId,
    required String userId,
  }) async {
    final orgId = _selectedGroup?.organizationId;
    if (orgId == null) return false;
    final result = await _groupRepo.blockMember(
      organizationId: orgId,
      groupId: groupId,
      userId: userId,
    );
    switch (result) {
      case Ok():
        _blockedIds.add(userId);
        // Remove from UI member list immediately
        _selectedGroupMembers =
            _selectedGroupMembers.where((m) => m.id != userId).toList();
        // Update the local _groups copy to reflect blockedMemberIds change
        final idx = _groups.indexWhere((g) => g.id == groupId);
        if (idx != -1) {
          final g = _groups[idx];
          final updated = g.copyWith(
            blockedMemberIds: [
              ...g.blockedMemberIds,
              if (!g.blockedMemberIds.contains(userId)) userId,
            ],
            memberIds: g.memberIds.where((id) => id != userId).toList(),
          );
          _groups = List.of(_groups)..[idx] = updated;
          if (_selectedGroup?.id == groupId) _selectedGroup = updated;
        }
        notifyListeners();
        return true;
      case Err():
        notifyListeners();
        return false;
    }
  }

  Future<bool> unblockMember({
    required String groupId,
    required String userId,
  }) async {
    final orgId = _selectedGroup?.organizationId;
    if (orgId == null) return false;
    final result = await _groupRepo.unblockMember(
      organizationId: orgId,
      groupId: groupId,
      userId: userId,
    );
    switch (result) {
      case Ok():
        _blockedIds.remove(userId);
        // Update the local _groups copy to reflect unblock
        final idx = _groups.indexWhere((g) => g.id == groupId);
        if (idx != -1) {
          final g = _groups[idx];
          final updated = g.copyWith(
            blockedMemberIds:
                g.blockedMemberIds.where((id) => id != userId).toList(),
          );
          _groups = List.of(_groups)..[idx] = updated;
          if (_selectedGroup?.id == groupId) _selectedGroup = updated;
        }
        notifyListeners();
        return true;
      case Err():
        notifyListeners();
        return false;
    }
  }

  // ── Promote to admin ───────────────────────────────────────────────────────

  Future<bool> promoteToAdmin({
    required String groupId,
    required String userId,
  }) async {
    final idx = _groups.indexWhere((g) => g.id == groupId);
    if (idx == -1) return false;

    _groups = List.of(_groups)
      ..[idx] = GroupModel(
        id: _groups[idx].id,
        organizationId: _groups[idx].organizationId,
        name: _groups[idx].name,
        type: _groups[idx].type,
        mealConfig: _groups[idx].mealConfig,
        memberIds: _groups[idx].memberIds,
        description: _groups[idx].description,
        adminId: userId, // promote user to admin
        maxMembers: _groups[idx].maxMembers,
        isActive: _groups[idx].isActive,
        joinCode: _groups[idx].joinCode,
        createdAt: _groups[idx].createdAt,
      );
    if (_selectedGroup?.id == groupId) {
      _selectedGroup = _groups[idx];
    }
    notifyListeners();
    return true;
  }
}

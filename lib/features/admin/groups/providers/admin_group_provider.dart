import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
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

  // GRP-004 / CFG-002/003/004: config-driven member-cap limits keyed by role
  // name (e.g. hostelAdmin=50), plus the floor and fallback. Loaded once from
  // GET /groups/limits so the create form bounds Maximum Members by the SELECTED
  // role without hardcoding anything.
  Map<String, int> _roleMemberLimits = const {};
  int _defaultRoleMemberLimit = 50;
  int _minMembers = 2;
  bool _limitsLoaded = false;

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

  /// GRP-004: minimum Maximum-Members an admin must set (config-driven floor).
  int get minMembers => _minMembers;
  bool get limitsLoaded => _limitsLoaded;

  /// GRP-004: the configured member cap for [role] (falls back to the default).
  int memberLimitForRole(UserRole role) =>
      _roleMemberLimits[role.name] ?? _defaultRoleMemberLimit;

  int get totalMembers => _groups.fold(0, (s, g) => s + g.memberCount);
  int get activeGroupCount => _groups.where((g) => g.isActive).length;

  // ── Load ──────────────────────────────────────────────────────────────────

  /// GRP-004 / CFG-002/003/004: load config-driven member-cap limits once so the
  /// create form can bound Maximum Members by the selected role. Fail-safe —
  /// keeps sensible defaults (min 2, cap = defaultRoleMemberLimit) on any error
  /// and never surfaces an error for this non-critical prefetch.
  Future<void> loadLimits() async {
    if (_limitsLoaded) return;
    final result = await _groupRepo.getGroupLimits();
    switch (result) {
      case Ok(:final value):
        final raw = value['roleMemberLimits'];
        if (raw is Map) {
          _roleMemberLimits = raw.map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          );
        }
        final def = value['defaultRoleMemberLimit'];
        if (def is num) _defaultRoleMemberLimit = def.toInt();
        final min = value['minMembers'];
        if (min is num) _minMembers = min.toInt();
        _limitsLoaded = true;
        notifyListeners();
      case Err():
        break;
    }
  }

  Future<void> loadGroups({
    required String organizationId,
    bool includeInactive = false,
  }) async {
    if (_isLoading) return;
    // Cache-first: paint last-known groups instantly, then refresh. Archived
    // views use a separate cache key so they never overwrite the active list.
    final cacheKey =
        'admin_groups:$organizationId${includeInactive ? ':all' : ''}';
    if (_groups.isEmpty) {
      _isLoading = true; // sync: first build shows the loader, never empty state
      _groups = await ResponseCacheService.instance.readList(
          cacheKey, GroupModel.fromJson, maxAge: const Duration(hours: 12));
    }
    _isLoading = _groups.isEmpty;
    _error = null;
    notifyListeners();

    final result = await _groupRepo.getOrganisationGroups(
      organizationId: organizationId,
      includeInactive: includeInactive,
    );

    switch (result) {
      case Ok(:final value):
        _groups = value.data;
        ResponseCacheService.instance
            .writeList(cacheKey, value.data, (g) => g.toJson());
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
    // Prefer the already-loaded list (instant). The detail screen calls
    // loadGroups() + selectGroup() without awaiting, so _groups can still be
    // empty here; in that case fetch the group by id from the API. Without this
    // fallback the detail/QR screen showed "Group not found" for the admin's
    // own group in live mode.
    _isLoading = true; // keep the detail screen on the loader until the group resolves (no "not found" flash)
    GroupModel? local;
    for (final g in _groups) {
      if (g.id == groupId) {
        local = g;
        break;
      }
    }
    _selectedGroup = local;
    // Clear stale meal/member lists immediately so UI shows loading state
    _selectedGroupMeals = [];
    _selectedGroupMembers = [];
    notifyListeners();

    if (_selectedGroup == null) {
      final result = await _groupRepo.getGroup(
        organizationId: organizationId,
        groupId: groupId,
      );
      switch (result) {
        case Ok(:final value):
          _selectedGroup = value;
        case Err():
          break; // leave null → detail screen shows its empty state
      }
    }

    _isLoading = false;
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

  /// Per-org, per-group cache key for the member directory.
  String _membersCacheKey(String orgId, String groupId) =>
      'group_members:$orgId:$groupId';

  /// Write-through: persist the current member list so the next open of this
  /// group's directory paints instantly. Called after load AND every member
  /// mutation, so the cache never lags what the admin just changed.
  void _cacheMembers(String orgId, String groupId) {
    ResponseCacheService.instance.writeList(
        _membersCacheKey(orgId, groupId), _selectedGroupMembers, (m) => m.toJson());
  }

  Future<void> loadGroupMembers({
    required String groupId,
    required String organizationId,
  }) async {
    // Cache-first (SWR): paint the last-known member directory instantly, then
    // refresh below. The network result always overwrites.
    if (_selectedGroupMembers.isEmpty) {
      _isLoadingMembers = true; // sync: loader, never an empty members flash
      _selectedGroupMembers = await ResponseCacheService.instance.readList(
          _membersCacheKey(organizationId, groupId), UserModel.fromJson,
          maxAge: const Duration(hours: 12));
    }
    _isLoadingMembers = _selectedGroupMembers.isEmpty;
    notifyListeners();

    final result = await _groupRepo.getGroupMembers(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok(:final value):
        _selectedGroupMembers = value.data;
        _cacheMembers(organizationId, groupId);
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
    UserRole? functionalRole,
    // Module 02 (GRP-003) — extended metadata + policy captured at creation.
    String? country,
    String? state,
    String? city,
    String? address,
    String? timezone,
    String? currency,
    bool? joinApprovalRequired,
    int? qrExpiryDays,
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
      functionalRole: functionalRole,
      country: country,
      state: state,
      city: city,
      address: address,
      timezone: timezone,
      currency: currency,
      joinApprovalRequired: joinApprovalRequired,
      qrExpiryDays: qrExpiryDays,
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
    UserRole? functionalRole,
  }) async {
    final result = await _groupRepo.updateGroup(
      organizationId: organizationId,
      groupId: groupId,
      name: name,
      type: type,
      description: description,
      mealConfig: mealConfig,
      maxMembers: maxMembers,
      functionalRole: functionalRole,
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

  /// GRP-018: restore an archived group (flips it back to active).
  Future<bool> restoreGroup(
    String groupId, {
    required String organizationId,
  }) async {
    final result = await _groupRepo.restoreGroup(groupId: groupId);
    switch (result) {
      case Ok(:final value):
        final idx = _groups.indexWhere((g) => g.id == groupId);
        if (idx != -1) {
          _groups = List.of(_groups)..[idx] = value;
        } else {
          _groups = [value, ..._groups];
        }
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  /// GRP-019: permanently delete a group and all its data (irreversible).
  Future<bool> permanentDeleteGroup(
    String groupId, {
    required String organizationId,
  }) async {
    final result = await _groupRepo.permanentDeleteGroup(groupId: groupId);
    switch (result) {
      case Ok():
        _groups = _groups.where((g) => g.id != groupId).toList();
        if (_selectedGroup?.id == groupId) _selectedGroup = null;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── Join approval workflow (MEM-006/007) ────────────────────────────────────

  /// Approve a pending join request; on success the member becomes active.
  Future<bool> approveJoinRequest({
    required String groupId,
    required String userId,
  }) async {
    final result =
        await _groupRepo.approveJoinRequest(groupId: groupId, userId: userId);
    switch (result) {
      case Ok():
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  /// Reject a pending join request with an optional reason.
  Future<bool> rejectJoinRequest({
    required String groupId,
    required String userId,
    String? reason,
  }) async {
    final result = await _groupRepo.rejectJoinRequest(
      groupId: groupId,
      userId: userId,
      reason: reason,
    );
    switch (result) {
      case Ok():
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
        _cacheMembers(organizationId, groupId); // write-through: no stale list
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
        _cacheMembers(orgId, groupId); // write-through: no stale list
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

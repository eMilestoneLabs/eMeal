import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';

/// Drives the student-side group join flow and group listing.
///
/// Manages: loading user's groups, joining by code, and loading a single group.
class GroupProvider extends ChangeNotifier {
  GroupProvider({GroupRepository? repository})
      : _repo = repository ?? GroupRepository();

  final GroupRepository _repo;

  // ── State ──────────────────────────────────────────────────────────────────

  List<GroupModel> _myGroups = [];
  GroupModel? _selectedGroup;
  bool _isLoading = false;
  bool _isJoining = false;
  String? _error;
  String? _joinError;
  GroupModel? _lastJoined; // Shown in success state after joining
  // Issue 4: the user's own pending join requests (server-truth), so the
  // "Waiting for approval" state is re-accessible after the inline flow closes.
  List<GroupModel> _pendingRequests = [];

  // ── Public getters ─────────────────────────────────────────────────────────

  List<GroupModel> get myGroups => _myGroups;
  List<GroupModel> get pendingRequests => _pendingRequests;
  bool get hasPendingRequests => _pendingRequests.isNotEmpty;
  GroupModel? get selectedGroup => _selectedGroup;
  bool get isLoading => _isLoading;
  bool get isJoining => _isJoining;
  String? get error => _error;
  String? get joinError => _joinError;
  GroupModel? get lastJoined => _lastJoined;
  bool get hasGroups => _myGroups.isNotEmpty;

  // ── Load my groups ─────────────────────────────────────────────────────────

  Future<void> loadMyGroups(
    String userId, {
    required String organizationId,
    bool forceRefresh = false,
  }) async {
    if (_isLoading) return;
    if (!forceRefresh && _myGroups.isNotEmpty) return;

    // Cache-first (modular helper): paint last-known groups instantly.
    final cacheKey = 'my_groups:$organizationId:$userId';
    if (_myGroups.isEmpty) {
      _isLoading = true; // sync: first build shows the loader, never empty state
      _myGroups = await ResponseCacheService.instance.readList(
          cacheKey, GroupModel.fromJson, maxAge: const Duration(hours: 12));
    }
    _isLoading = _myGroups.isEmpty;
    _error = null;
    notifyListeners();

    final result = await _repo.getMyGroups(
      userId,
      organizationId: organizationId,
    );

    switch (result) {
      case Ok(:final value):
        _myGroups = value;
        _error = null;
        ResponseCacheService.instance
            .writeList(cacheKey, value, (g) => g.toJson());
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Load single group ──────────────────────────────────────────────────────

  Future<void> loadGroup({
    required String organizationId,
    required String groupId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repo.getGroupById(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok(:final value):
        _selectedGroup = value;
        _error = null;
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Join by code ───────────────────────────────────────────────────────────

  /// Attempt to join a group by [joinCode].
  ///
  /// Returns true on success, false on failure.
  /// Sets [lastJoined] on success so the UI can show a confirmation.
  Future<bool> joinByCode({
    required String userId,
    required String joinCode,
    required String organizationId,
    String? functionalRole,
  }) async {
    if (_isJoining) return false;

    _isJoining = true;
    _joinError = null;
    _lastJoined = null;
    notifyListeners();

    final result = await _repo.joinGroupByCode(
      userId: userId,
      joinCode: joinCode.trim().toUpperCase(),
      organizationId: organizationId,
      // #2: the member's chosen per-group display role (member-level only).
      functionalRole: functionalRole,
    );

    bool success = false;
    switch (result) {
      case Ok(:final value):
        _lastJoined = value;
        // MEM-004: a PENDING join is awaiting approval — the member is NOT yet
        // active, so it must not enter the active groups list.
        if (!value.isPendingApproval) {
          final idx = _myGroups.indexWhere((g) => g.id == value.id);
          if (idx >= 0) {
            _myGroups[idx] = value;
          } else {
            _myGroups = [..._myGroups, value];
          }
        }
        success = true;
      case Err(:final failure):
        // "Already a member" is a soft error — treat as success so the
        // UI can still navigate the user to the group they belong to.
        if (failure.message.contains('already a member')) {
          // Try to find the group in the existing list so we can show
          // the success state without the API returning the group object.
          final existing = _myGroups.where(
            (g) => g.joinCode == joinCode.trim().toUpperCase(),
          ).firstOrNull;
          if (existing != null) {
            _lastJoined = existing;
            success = true;
          } else {
            _joinError = failure.message;
            success = false;
          }
        } else {
          _joinError = failure.message;
          success = false;
        }
    }

    _isJoining = false;
    notifyListeners();
    return success;
  }

  // ── Leave group ────────────────────────────────────────────────────────────

  /// MEM-016/017: self-service leave. Uses the dedicated member endpoint (the
  /// old path called the admin-only removeMember route, which 403'd for a
  /// student leaving their own group).
  Future<bool> leaveGroup({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    final result = await _repo.leaveGroup(groupId: groupId);

    switch (result) {
      case Ok():
        _myGroups.removeWhere((g) => g.id == groupId);
        if (_selectedGroup?.id == groupId) _selectedGroup = null;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── Join preview (MEM-002) ──────────────────────────────────────────────────

  /// Pre-join preview: identity, capacity and whether approval is required.
  /// Returns null on failure (caller shows [joinError]).
  Future<Map<String, dynamic>?> previewJoin(String joinCode) async {
    final result = await _repo.previewJoin(joinCode: joinCode.trim());
    switch (result) {
      case Ok(:final value):
        return value;
      case Err(:final failure):
        _joinError = failure.message;
        notifyListeners();
        return null;
    }
  }

  // ── Pending join requests (MEM-004/005, Issue 4) ────────────────────────────

  /// Load the user's own pending join requests (server-truth). Silent refresh:
  /// a request an admin has since acted on simply drops off the list.
  Future<void> loadPendingRequests() async {
    final result = await _repo.getMyJoinRequests();
    if (result case Ok(:final value)) {
      _pendingRequests = value;
      notifyListeners();
    }
  }

  // ── Cancel pending request (MEM-005) ────────────────────────────────────────

  /// Cancel the member's own pending join request.
  Future<bool> cancelPendingRequest(String groupId) async {
    final result = await _repo.cancelJoinRequest(groupId: groupId);
    switch (result) {
      case Ok():
        if (_lastJoined?.id == groupId) _lastJoined = null;
        // Issue 4: keep the re-accessible pending list in sync after a cancel.
        _pendingRequests.removeWhere((g) => g.id == groupId);
        notifyListeners();
        return true;
      case Err(:final failure):
        _joinError = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void clearJoinError() {
    if (_joinError == null) return;
    _joinError = null;
    notifyListeners();
  }

  void clearLastJoined() {
    if (_lastJoined == null) return;
    _lastJoined = null;
    notifyListeners();
  }
}

import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

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

  // ── Public getters ─────────────────────────────────────────────────────────

  List<GroupModel> get myGroups => _myGroups;
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

    _isLoading = true;
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
    );

    bool success = false;
    switch (result) {
      case Ok(:final value):
        _lastJoined = value;
        // Add / update in myGroups list
        final idx = _myGroups.indexWhere((g) => g.id == value.id);
        if (idx >= 0) {
          _myGroups[idx] = value;
        } else {
          _myGroups = [..._myGroups, value];
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

  Future<bool> leaveGroup({
    required String organizationId,
    required String groupId,
    required String userId,
  }) async {
    final result = await _repo.removeMember(
      organizationId: organizationId,
      groupId: groupId,
      userId: userId,
    );

    switch (result) {
      case Ok():
        _myGroups.removeWhere((g) => g.id == groupId);
        if (_selectedGroup?.id == groupId) _selectedGroup = null;
        notifyListeners();
        return true;
      case Err():
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

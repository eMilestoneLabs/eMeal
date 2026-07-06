import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';

/// MODULE_02 (GRP-006/007, MEM-013/015) — device-local, per-user ordering for
/// the Group Switcher / group lists.
///
/// The chosen order is a UI preference (like "last selected group"), so it is
/// persisted on-device with `shared_preferences` — no backend, no API change,
/// no migration. Newly created / newly joined groups that are not yet in the
/// saved order appear FIRST (GRP-006), preserving the SRS default.
class GroupOrderService {
  GroupOrderService._();
  static final GroupOrderService instance = GroupOrderService._();

  String _key(String userId) => 'group_order:$userId';

  /// The saved order of group ids for [userId] (empty when never set).
  Future<List<String>> load(String userId) async {
    if (userId.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key(userId)) ?? const [];
  }

  /// Persist the new [orderedIds] for [userId].
  Future<void> save(String userId, List<String> orderedIds) async {
    if (userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(userId), orderedIds);
  }

  /// Reorder [ids] by the [saved] preference: any id NOT in [saved] (a new
  /// group) comes first (GRP-006), followed by the saved order (filtered to
  /// ids that still exist). Pure + null-safe.
  List<String> applyToIds(List<String> ids, List<String> saved) {
    if (saved.isEmpty) return List<String>.from(ids);
    final present = ids.toSet();
    final savedSet = saved.toSet();
    final newFirst = ids.where((id) => !savedSet.contains(id)); // GRP-006
    final inSavedOrder = saved.where(present.contains);
    return [...newFirst, ...inSavedOrder];
  }

  /// Reorder [groups] by the [saved] preference (see [applyToIds]).
  List<GroupModel> applyToGroups(
    List<GroupModel> groups,
    List<String> saved,
  ) {
    if (saved.isEmpty) return groups;
    final byId = {for (final g in groups) g.id: g};
    final orderedIds = applyToIds(groups.map((g) => g.id).toList(), saved);
    return [
      for (final id in orderedIds)
        if (byId[id] != null) byId[id]!,
    ];
  }
}

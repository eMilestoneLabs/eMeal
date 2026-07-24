import 'package:shared_preferences/shared_preferences.dart';

/// ISSUE-003 (Live-Test-12): ONE source of truth for the admin's selected
/// group across every tab — Home dashboard, Meals (Master Meal Template /
/// Planner), Attendance, Billing, Exports, Notices.
///
/// Before this store each tab resolved its own "current group" (dashboard:
/// persisted default; Meals: first group; Attendance: the admin's own
/// membership; Billing: first group), so switching the group on Home left the
/// other tabs on a different group. Every tab now reads the LAST EXPLICITLY
/// SELECTED group from here first and writes back every explicit switch, so
/// the selection is stable app-wide and across restarts.
///
/// Storage: SharedPreferences, org-scoped key (`admin_default_group_id:<org>`)
/// with the legacy unscoped `admin_default_group_id` kept in sync for
/// backward compatibility (CacheWarmer and older readers). Org scoping means
/// an account/org switch can never leak the previous org's selection — and
/// callers additionally validate the stored id against the live group list
/// before using it (a stale/foreign id simply falls through to their default).
class SelectedGroupStore {
  SelectedGroupStore._();
  static final SelectedGroupStore instance = SelectedGroupStore._();

  /// Legacy key the dashboard already persisted — kept written for
  /// compatibility with existing readers (CacheWarmer).
  static const String legacyKey = 'admin_default_group_id';

  String _scopedKey(String organizationId) =>
      'admin_default_group_id:$organizationId';

  /// In-memory copy of the last read/write per org — sync access for callers
  /// that already awaited [read] once this session.
  final Map<String, String?> _memory = {};

  /// Last-known selection for [organizationId] without touching disk
  /// (null when never read/written this session).
  String? peek(String organizationId) => _memory[organizationId];

  /// The persisted selected group for this org — org-scoped value first,
  /// legacy unscoped fallback (pre-store installs).
  Future<String?> read(String organizationId) async {
    if (_memory.containsKey(organizationId)) return _memory[organizationId];
    try {
      final prefs = await SharedPreferences.getInstance();
      final v =
          prefs.getString(_scopedKey(organizationId)) ??
              prefs.getString(legacyKey);
      _memory[organizationId] = v;
      return v;
    } catch (_) {
      return null; // prefs unavailable — caller falls back to its default
    }
  }

  /// ISSUE-003: full wipe on account change — clears the in-memory copies
  /// AND every persisted selection key (org-scoped + legacy), so a new
  /// account can never inherit the previous account's group selection.
  /// Called from the auth cache-ownership adoption alongside the SWR clear.
  Future<void> clearAll() async {
    _memory.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs
          .getKeys()
          .where((k) => k == legacyKey || k.startsWith('$legacyKey:'))
          .toList()) {
        await prefs.remove(k);
      }
    } catch (_) {/* best-effort */}
  }

  /// Persist an explicit group selection (null clears it). Fire-and-forget
  /// safe — failures never surface to the UI.
  Future<void> write(String organizationId, String? groupId) async {
    _memory[organizationId] = groupId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (groupId == null) {
        await prefs.remove(_scopedKey(organizationId));
        await prefs.remove(legacyKey);
      } else {
        await prefs.setString(_scopedKey(organizationId), groupId);
        await prefs.setString(legacyKey, groupId);
      }
    } catch (_) {/* best-effort persistence */}
  }
}

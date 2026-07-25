import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One app-wide group-selection change: which org it belongs to and the group
/// that is now selected (null = selection cleared, e.g. account switch).
///
/// Carrying the org makes every listener tenant-safe by construction: a
/// listener bound to org A simply ignores a change published for org B, so a
/// stale notifier can never point a screen at another organisation's group.
@immutable
class SelectedGroupChange {
  const SelectedGroupChange(this.organizationId, this.groupId);

  final String organizationId;
  final String? groupId;

  @override
  bool operator ==(Object other) =>
      other is SelectedGroupChange &&
      other.organizationId == organizationId &&
      other.groupId == groupId;

  @override
  int get hashCode => Object.hash(organizationId, groupId);
}

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

  /// ISSUE-003 (Live-Test-13): the selection is now BROADCAST, not just
  /// persisted. Before this, every tab read the store on init and wrote it on
  /// switch, but nothing told the OTHER tabs — so switching the group on the
  /// Weekly Menu (or while marking attendance) left Home/Billing/Attendance
  /// showing the previous group until they happened to rebuild. Every
  /// group-scoped provider/screen now listens here and reloads for the new
  /// group the instant it changes, from wherever the switch was made.
  ///
  /// Fires ONLY on an actual value change (see [write]), so listeners never
  /// see redundant events and the existing SWR/cache-first paint work is not
  /// repeated — no extra network calls, no rebuild storms.
  final ValueNotifier<SelectedGroupChange?> selection =
      ValueNotifier<SelectedGroupChange?>(null);

  /// Publish a change to every listener. Private: the value is only ever
  /// broadcast as a side effect of [write]/[clearAll], so the notifier can
  /// never disagree with what is persisted.
  void _broadcast(String organizationId, String? groupId) {
    selection.value = SelectedGroupChange(organizationId, groupId);
  }

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
    // ISSUE-003: drop the broadcast value too — a listener that outlives the
    // sign-out must never re-apply the previous account's group. Reset to null
    // (rather than a change event) so no listener treats it as a selection.
    selection.value = null;
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
    // ISSUE-003: broadcast BEFORE the (slow, best-effort) disk write and only
    // when the value actually changed — listeners react in the same frame as
    // the tap, and a re-select of the already-current group stays a no-op.
    final changed =
        !_memory.containsKey(organizationId) || _memory[organizationId] != groupId;
    _memory[organizationId] = groupId;
    if (changed) _broadcast(organizationId, groupId);
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

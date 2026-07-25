import 'package:flutter/foundation.dart';

import 'package:smart_meal_management/data/services/selected_group_store.dart';

/// ISSUE-003 (Live-Test-13): one reusable subscription to the app-wide group
/// selection published by [SelectedGroupStore].
///
/// Why a helper: every group-scoped provider/screen (Home dashboard, Meals /
/// Master Meal Template / Planner, Attendance, Billing, Exports, Weekly Menu)
/// needs the exact same three guards when the selection changes elsewhere —
/// ignore other organisations, ignore a cleared selection, ignore a change to
/// the group it is ALREADY showing. Duplicating that in every consumer is how the
/// selection drifted apart in the first place, so it lives here once — one
/// place to reason about, one place to change.
///
/// Guarantees:
/// * **Tenant-safe** — a change published for another organisation is dropped,
///   so a listener can never be pointed at another org's group.
/// * **Loop-free** — the store only publishes on a real value change, and the
///   caller's own `isCurrent` check suppresses the echo of its own write, so a
///   provider that writes the selection never reloads itself twice.
/// * **Leak-free** — [cancel] detaches; call it from the owner's `dispose`.
class SelectedGroupSubscription {
  SelectedGroupSubscription._(this._handler);

  final VoidCallback _handler;
  bool _cancelled = false;

  /// Listen for group switches made ANYWHERE in the app for [organizationId].
  ///
  /// [isCurrent] returns true when the incoming group is the one the caller is
  /// already showing — the caller's own write echoes back through the notifier
  /// and must not trigger a second, redundant reload.
  /// [onChanged] is invoked only for a genuinely different group of this org.
  static SelectedGroupSubscription bind({
    required String organizationId,
    required bool Function(String groupId) isCurrent,
    required void Function(String groupId) onChanged,
  }) {
    void handler() {
      final change = SelectedGroupStore.instance.selection.value;
      if (change == null) return; // cleared (sign-out / account switch)
      if (change.organizationId != organizationId) return; // tenant guard
      final groupId = change.groupId;
      if (groupId == null || groupId.isEmpty) return;
      if (isCurrent(groupId)) return; // echo of our own switch — no-op
      onChanged(groupId);
    }

    SelectedGroupStore.instance.selection.addListener(handler);
    return SelectedGroupSubscription._(handler);
  }

  /// Detach from the store. Idempotent — safe to call from `dispose` twice.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    SelectedGroupStore.instance.selection.removeListener(_handler);
  }
}

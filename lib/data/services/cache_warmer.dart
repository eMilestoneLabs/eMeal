import 'dart:async';

import 'package:smart_meal_management/features/admin/attendance/providers/admin_attendance_provider.dart';
import 'package:smart_meal_management/features/admin/groups/providers/admin_group_provider.dart';
import 'package:smart_meal_management/features/admin/meals/providers/meal_config_provider.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/groups/providers/group_provider.dart';
import 'package:smart_meal_management/features/student/attendance/providers/student_attendance_provider.dart';
import 'package:smart_meal_management/features/student/profile/providers/student_profile_provider.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Warms the SWR response cache for the **non-landing** tabs right after a
/// session is established, so the *first* open of each tab is an instant
/// cache hit instead of a cold network round-trip over a high-latency link.
///
/// Design:
///   • **Reuses each provider's own `load()`** — the warmer constructs a
///     throwaway provider, calls its loader, and disposes it. The provider
///     writes its own cache key, so there is **zero key duplication** here and
///     no risk of the warmer drifting from what the screens actually read.
///   • **Fire-and-forget + fully best-effort** — every task runs detached and
///     swallows its own errors, so warming can never block the UI, slow login,
///     or surface a failure to the user.
///   • **No double-fetch** — the dashboard (the landing tab) and the weekly
///     menu are already loaded/prefetched by the dashboard provider, so they
///     are deliberately excluded here.
///   • **No leaks** — every throwaway provider is disposed in a `finally`
///     (important for [StudentProfileProvider], which registers an auth
///     listener in its constructor).
///   • **Tenant-safe** — providers derive their keys from the session's
///     org/group/user ids, and the whole cache is cleared on logout.
class CacheWarmer {
  CacheWarmer._();

  static final CacheWarmer instance = CacheWarmer._();

  /// Id of the user we have already warmed for. `didChangeDependencies` (the
  /// shell hook) can fire many times, so warming must run **once per account**:
  /// keying the guard on the user id also makes account-switching self-healing
  /// (a different account warms fresh) with no logout coupling required.
  String? _warmedUserId;

  /// Warm the student tabs: attendance records, 30-day profile summary, and the
  /// member's groups. Dashboard + weekly menu are warmed by the dashboard.
  void warmStudent(UserModel user, {required AuthProvider auth}) {
    if (_warmedUserId == user.id) return;
    _warmedUserId = user.id;

    final orgId = user.organizationId;
    if (orgId.isEmpty) return;
    final groupId =
        user.effectiveGroupIds.isNotEmpty ? user.effectiveGroupIds.first : null;

    if (groupId != null) {
      _run(() async {
        final p = StudentAttendanceProvider();
        try {
          await p.load(
            userId: user.id,
            groupId: groupId,
            organizationId: orgId,
          );
        } finally {
          p.dispose();
        }
      });
    }

    _run(() async {
      final p = StudentProfileProvider(authProvider: auth);
      try {
        await p.loadSummary();
      } finally {
        p.dispose();
      }
    });

    _run(() async {
      final p = GroupProvider();
      try {
        await p.loadMyGroups(user.id, organizationId: orgId);
      } finally {
        p.dispose();
      }
    });
  }

  /// Warm the admin tabs: organisation groups, meal-config groups, and today's
  /// attendance for the first group (the Attendance tab's default view).
  /// Dashboard is warmed by its own landing load.
  void warmAdmin(UserModel user) {
    if (_warmedUserId == user.id) return;
    _warmedUserId = user.id;

    final orgId = user.organizationId;
    if (orgId.isEmpty) return;

    _run(() async {
      final p = AdminGroupProvider();
      try {
        await p.loadGroups(organizationId: orgId);
        // Chain: warm today's attendance for the first group — the default the
        // Attendance tab opens on — so it too is an instant cache hit.
        final first = p.groups.isNotEmpty ? p.groups.first : null;
        if (first != null) {
          final a = AdminAttendanceProvider();
          try {
            await a.load(groupId: first.id, organizationId: orgId);
          } finally {
            a.dispose();
          }
        }
      } finally {
        p.dispose();
      }
    });

    _run(() async {
      final p = MealConfigProvider();
      try {
        await p.loadGroups(organizationId: orgId);
      } finally {
        p.dispose();
      }
    });
  }

  /// Runs [task] detached, isolating any failure so one task can never affect
  /// another or the caller. Warming is purely an optimisation; failures are
  /// silently ignored (the screen will simply fetch on first open, as before).
  void _run(Future<void> Function() task) {
    unawaited(() async {
      try {
        await task();
      } catch (_) {
        /* best-effort warm — never surfaces to the user */
      }
    }());
  }
}

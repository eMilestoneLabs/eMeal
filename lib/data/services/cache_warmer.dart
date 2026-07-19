import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/features/admin/attendance/providers/admin_attendance_provider.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
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

  /// Upper bound on avatars prefetched per warm — keeps the background data
  /// cost small on very large groups (the rest load on demand, as before).
  static const int _maxAvatarPrefetch = 30;

  /// Signature of the session we have already warmed for.
  /// `didChangeDependencies` (the shell hook) can fire many times, so warming
  /// must run **once per account state** — but "state" is more than the user
  /// id: a brand-new student joins a group (org + groupIds appear) and a
  /// brand-new admin creates their first group, and in both cases every cache
  /// key changes, so the old warm is worthless. Keying the guard on
  /// user + org + memberships makes those transitions self-healing (the next
  /// shell hook re-warms with the fresh scope), and account-switching stays
  /// self-healing exactly as before with no logout coupling required.
  String? _warmedSignature;

  /// Composite warm signature — any org/membership change re-warms.
  static String _signatureFor(UserModel user) {
    final groups = user.effectiveGroupIds.toList()..sort();
    return '${user.id}|${user.organizationId}|${groups.join(',')}';
  }

  /// Drops the warm guard so the **next shell hook re-warms** with fresh data.
  /// Call after account-shape writes the user model alone cannot signal —
  /// e.g. an admin creating a group (org/memberships unchanged, but the
  /// groups/attendance/meals caches all change scope). Fire-and-forget safe.
  void rewarm() {
    _warmedSignature = null;
  }

  /// Warm the student tabs: attendance records, 30-day profile summary, and the
  /// member's groups. Dashboard + weekly menu are warmed by the dashboard.
  void warmStudent(UserModel user, {required AuthProvider auth}) {
    final signature = _signatureFor(user);
    if (_warmedSignature == signature) return;
    _warmedSignature = signature;

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
    final signature = _signatureFor(user);
    if (_warmedSignature == signature) return;
    _warmedSignature = signature;

    final orgId = user.organizationId;
    if (orgId.isEmpty) return;

    _run(() async {
      final p = AdminGroupProvider();
      try {
        await p.loadGroups(organizationId: orgId);
        if (p.groups.isEmpty) return;
        // Chain: warm today's attendance + the member directory for the
        // admin's DEFAULT group — the one the Attendance tab and group detail
        // actually open on (saved via the dashboard's group selector; falls
        // back to the first group) — so both are instant cache hits.
        final prefs = await SharedPreferences.getInstance();
        final savedId =
            prefs.getString(AdminDashboardProvider.kDefaultGroupKey);
        final target = p.groups.firstWhere(
          (g) => g.id == savedId,
          orElse: () => p.groups.first,
        );
        final a = AdminAttendanceProvider();
        try {
          await a.load(groupId: target.id, organizationId: orgId);
        } finally {
          a.dispose();
        }
        // Member directory + configured meals (write-through caches inside
        // the provider; the meals cache is SHARED with Meal Config and the
        // group-detail Meals tab, so all three open instantly) — one wave.
        await Future.wait([
          p.loadGroupMembers(
            groupId: target.id,
            organizationId: orgId,
          ),
          p.loadGroupMeals(
            groupId: target.id,
            organizationId: orgId,
          ),
        ]);
        // Prefetch the members' avatars into the image disk cache (the one
        // CachedNetworkImage reads) so the directory's photos render instantly
        // on first open — not just the names. Bounded + best-effort: each
        // download is independent and a failure only means the avatar loads
        // on demand, exactly as before.
        final avatarUrls = p.selectedGroupMembers
            .map((m) => m.avatarUrl)
            .whereType<String>()
            .where((u) => u.startsWith('https://') || u.startsWith('http://'))
            .take(_maxAvatarPrefetch)
            .toList();
        for (final url in avatarUrls) {
          _run(() async {
            await DefaultCacheManager().downloadFile(url);
          });
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

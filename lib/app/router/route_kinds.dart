import 'package:smart_meal_management/app/router/route_names.dart';

/// How a route is meant to be entered — the knowledge that was implicit and
/// therefore got guessed wrong.
///
/// Live-Test-16: `/student/settings` was reached with `context.go` from two
/// call sites and `context.push` from two others. `go` REPLACES the shell's
/// only page, so the screen rendered with no back arrow
/// (`automaticallyImplyLeading` saw an unpoppable navigator) and Android back
/// closed the app. Nothing in the codebase recorded that Settings is a leaf
/// and Meals is a tab, so each call site had to guess. This map is that record.
enum RouteKind {
  /// A bottom-nav destination. Enter with `context.go` — a tab switch must
  /// REPLACE, not stack. Back from a tab returns to Home (see
  /// `ShellBackHandler`).
  ///
  /// A tab may also be `push`ed on purpose as a drill-down (the admin
  /// dashboard's quick actions do this for Groups / Meals / Attendance), which
  /// is safe because a push always leaves something to pop. That is why the
  /// guard in `test/route_kind_guard_test.dart` is one-directional.
  tab,

  /// A sub-screen entered from somewhere else. Enter with `context.push` so it
  /// gets a back arrow and back returns to the caller. **Never `go` here** —
  /// that is the defect above.
  leaf,

  /// A session/stack boundary (splash, role select, post-login landing, event
  /// entry). Enter with `context.go`: the previous stack must NOT be reachable
  /// by pressing back.
  reset,
}

/// The single source of truth for route kind, and — via [isRegisteredRoute] —
/// for which paths a notification payload may legitimately target.
///
/// Keys are exactly the paths that were deep-link-addressable before this map
/// existed; `test/route_kind_guard_test.dart` pins that set so the behaviour of
/// [isRegisteredRoute] cannot drift. Adding a route here makes it BOTH
/// classified and deep-linkable, so add deliberately.
///
/// Auth routes (`/login`, `/otp`, the signup screens) are intentionally absent:
/// they were never notification targets and must not become one.
const Map<String, RouteKind> kRouteKinds = {
  // ── Entry / session boundaries ───────────────────────────────────────────
  RouteNames.splash: RouteKind.reset,
  RouteNames.roleSelect: RouteKind.reset,

  // ── Student shell ────────────────────────────────────────────────────────
  RouteNames.studentDashboard: RouteKind.tab, // home
  RouteNames.studentMeals: RouteKind.tab,
  RouteNames.studentAttendance: RouteKind.tab,
  RouteNames.studentWeeklyMenu: RouteKind.tab,
  RouteNames.studentProfile: RouteKind.tab,
  RouteNames.studentAttendanceHistory: RouteKind.leaf,
  RouteNames.studentSettings: RouteKind.leaf,
  RouteNames.studentBilling: RouteKind.leaf,

  // ── Admin shell ──────────────────────────────────────────────────────────
  RouteNames.adminDashboard: RouteKind.tab, // home
  RouteNames.adminGroups: RouteKind.tab,
  RouteNames.adminMealConfig: RouteKind.tab,
  RouteNames.adminAttendance: RouteKind.tab,
  RouteNames.adminMore: RouteKind.tab,
  RouteNames.adminMealSchedule: RouteKind.leaf, // pushed from Meal Config
  RouteNames.adminExports: RouteKind.leaf, // pushed from More / quick action
  RouteNames.adminBilling: RouteKind.leaf, // pushed from a quick action
  RouteNames.adminSettings: RouteKind.leaf, // pushed from More / Profile
  RouteNames.adminProfile: RouteKind.leaf, // pushed from More
  RouteNames.adminMyAttendance: RouteKind.leaf, // pushed from More

  // ── Shared ───────────────────────────────────────────────────────────────
  RouteNames.groupJoin: RouteKind.leaf,
  RouteNames.notepad: RouteKind.leaf,

  // ── Events ───────────────────────────────────────────────────────────────
  RouteNames.eventAdminRoot: RouteKind.reset,
  RouteNames.eventAdminCreate: RouteKind.leaf, // pushed from the landing list
  RouteNames.eventAdminDashboard: RouteKind.reset, // legacy redirect target
  RouteNames.eventGuestJoin: RouteKind.reset,
  RouteNames.eventGuestDashboard: RouteKind.reset,
};

/// Dynamic route families (path-parameter sub-trees) that pass through.
///
/// Both are entered with `push` from their list screen, i.e. [RouteKind.leaf],
/// but they cannot be map keys because the concrete path carries an id.
const List<String> kRouteKindPrefixes = [
  '/admin/groups/',
  '/event-admin/event/',
];

/// Whether [route] is a path the router actually registers.
///
/// Live-Test-11 ISSUE-001: deep-links may carry query intents
/// (e.g. `/admin/attendance?open=corrections`) — match on the path alone.
bool isRegisteredRoute(String route) {
  final path = route.split('?').first;
  if (kRouteKinds.containsKey(path)) return true;
  for (final p in kRouteKindPrefixes) {
    if (path.startsWith(p)) return true;
  }
  return false;
}

/// The kind of [route], or null when it is not a registered exact path.
/// Prefix families resolve to [RouteKind.leaf].
RouteKind? routeKindOf(String route) {
  final path = route.split('?').first;
  final exact = kRouteKinds[path];
  if (exact != null) return exact;
  for (final p in kRouteKindPrefixes) {
    if (path.startsWith(p)) return RouteKind.leaf;
  }
  return null;
}

import 'package:smart_meal_management/app/router/route_kinds.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';

/// Resolves a notification deep-link payload to a route that is actually
/// registered in the application router (Issue 6 — billing notification
/// opened the 404 screen).
///
/// Older backend payloads carry role-agnostic routes (`/billing`,
/// `/attendance`, `/settings`, `/notices`) while the router only registers
/// the role-prefixed forms (`/student/billing`, `/admin/billing`, …).
/// This maps every known legacy route to the correct screen for the
/// signed-in role, passes registered routes through untouched, and sends
/// anything still unknown to the role dashboard — a tapped notification
/// never dead-ends on 404.
String resolveNotificationRoute(String payload, AuthProvider auth) {
  final route = payload.trim();
  if (route.isEmpty) return _dashboardOf(auth);

  final user = auth.currentUser;
  final isAdmin = user != null && user.role.isAdminGroup;

  switch (route) {
    case '/billing':
      return isAdmin ? RouteNames.adminBilling : RouteNames.studentBilling;
    case '/attendance':
      return isAdmin ? RouteNames.adminAttendance : RouteNames.studentAttendance;
    case '/settings':
      return isAdmin ? RouteNames.adminSettings : RouteNames.studentSettings;
    // The notice feed opens from the dashboard bell (no standalone route).
    case '/notices':
      return _dashboardOf(auth);
  }

  if (isRegisteredRoute(route)) return route;

  // Unknown destination: land on the role home instead of the 404 screen.
  return _dashboardOf(auth);
}

// Live-Test-16: the registered-path list and the prefix list used to live here
// as `_knownRoutes` / `_knownPrefixes`. They moved verbatim to
// `route_kinds.dart` (`kRouteKinds` / `kRouteKindPrefixes`), which also records
// HOW each route is meant to be entered (tab / leaf / reset) — the knowledge
// whose absence let `/student/settings` be reached with `go` from two call
// sites and `push` from two others. Same 28 paths, same prefixes, same
// matching rule: `test/route_kind_guard_test.dart` pins the set so deep-link
// behaviour cannot drift.

String _dashboardOf(AuthProvider auth) {
  final user = auth.currentUser;
  if (user == null) return RouteNames.roleSelect;
  if (user.role.isAdminGroup) return RouteNames.adminDashboard;
  if (user.role == UserRole.eventAdmin) return RouteNames.eventAdminRoot;
  if (user.role == UserRole.eventGuest) return RouteNames.eventGuestDashboard;
  return RouteNames.studentDashboard;
}

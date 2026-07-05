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

  if (_isRegisteredRoute(route)) return route;

  // Unknown destination: land on the role home instead of the 404 screen.
  return _dashboardOf(auth);
}

/// Exact registered paths a notification may legitimately target.
const Set<String> _knownRoutes = {
  RouteNames.splash,
  RouteNames.roleSelect,
  RouteNames.studentDashboard,
  RouteNames.studentMeals,
  RouteNames.studentAttendance,
  RouteNames.studentAttendanceHistory,
  RouteNames.studentWeeklyMenu,
  RouteNames.studentProfile,
  RouteNames.studentSettings,
  RouteNames.studentBilling,
  RouteNames.adminDashboard,
  RouteNames.adminMealConfig,
  RouteNames.adminMealSchedule,
  RouteNames.adminAttendance,
  RouteNames.adminGroups,
  RouteNames.adminExports,
  RouteNames.adminBilling,
  RouteNames.adminSettings,
  RouteNames.adminProfile,
  RouteNames.adminMore,
  RouteNames.adminMyAttendance,
  RouteNames.groupJoin,
  RouteNames.notepad,
  RouteNames.eventAdminRoot,
  RouteNames.eventAdminCreate,
  RouteNames.eventAdminDashboard,
  RouteNames.eventGuestJoin,
  RouteNames.eventGuestDashboard,
};

/// Dynamic route families (path-parameter sub-trees) that pass through.
const List<String> _knownPrefixes = [
  '/admin/groups/',
  '/event-admin/event/',
];

bool _isRegisteredRoute(String route) {
  if (_knownRoutes.contains(route)) return true;
  for (final p in _knownPrefixes) {
    if (route.startsWith(p)) return true;
  }
  return false;
}

String _dashboardOf(AuthProvider auth) {
  final user = auth.currentUser;
  if (user == null) return RouteNames.roleSelect;
  if (user.role.isAdminGroup) return RouteNames.adminDashboard;
  if (user.role == UserRole.eventAdmin) return RouteNames.eventAdminRoot;
  if (user.role == UserRole.eventGuest) return RouteNames.eventGuestDashboard;
  return RouteNames.studentDashboard;
}

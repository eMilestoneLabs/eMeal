/// All named route paths for the application.
///
/// Use these constants everywhere instead of raw strings to ensure
/// compile-time safety across the entire routing graph.
abstract final class RouteNames {
  // Entry
  static const String splash = '/';
  static const String roleSelect = '/role-select';

  // Auth
  /// Login screen. Pass [AuthRouteExtra] via GoRouter extra:
  /// context.push(RouteNames.login, extra: AuthRouteExtra(roleContext: 'student'))
  static const String login = '/login';
  static const String otp = '/otp';
  static const String studentSignup = '/signup/student';
  static const String adminSignup = '/signup/admin';
  static const String eventSignup = '/signup/event';

  /// Event entry selection: choose Admin or Guest before login/scan.
  static const String eventEntry = '/event-entry';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  // Student
  static const String studentRoot = '/student';
  static const String studentDashboard = '/student/dashboard';
  static const String studentMeals = '/student/meals';
  static const String studentAttendance = '/student/attendance';
  static const String studentAttendanceHistory = '/student/attendance/history';
  static const String studentWeeklyMenu = '/student/menu';
  static const String studentProfile = '/student/profile';
  static const String studentSettings = '/student/settings';

  // Admin / Manager
  static const String adminRoot = '/admin';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminMealConfig = '/admin/meals';
  static const String adminMealSchedule = '/admin/meals/schedule';
  static const String adminAttendance = '/admin/attendance';
  static const String adminGroups = '/admin/groups';
  static const String adminGroupDetail = '/admin/groups/:groupId';
  static const String adminExports = '/admin/exports';
  static const String adminBilling = '/admin/billing';
  static const String adminSettings = '/admin/settings';
  static const String adminProfile = '/admin/profile';
  static const String adminMore = '/admin/more';

  // Groups (shared — accessed by students and admins)
  static const String groupJoin = '/groups/join';

  // Events — Admin
  /// Landing screen: list of admin's events + create new event.
  static const String eventAdminRoot = '/event-admin';

  /// Specific event shell (4-tab: Dashboard, Guests, Meals, Settings).
  /// Path param: :eventId
  static const String eventAdminEvent = '/event-admin/event/:eventId';

  /// Create new event form.
  static const String eventAdminCreate = '/event-admin/create';

  /// Legacy / redirect target — kept for router compat.
  static const String eventAdminDashboard = '/event-admin/dashboard';

  // Events — Guest
  static const String eventGuestJoin = '/event-guest/join';
  static const String eventGuestDashboard = '/event-guest';
}

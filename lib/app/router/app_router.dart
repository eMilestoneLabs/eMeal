import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';
import 'package:smart_meal_management/features/admin/admin_shell.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/admin_attendance_screen.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/staff_attendance_screen.dart';
import 'package:smart_meal_management/features/admin/dashboard/screens/admin_dashboard_screen.dart';
import 'package:smart_meal_management/features/admin/exports/screens/export_screen.dart';
import 'package:smart_meal_management/features/admin/billing/screens/billing_screen.dart';
import 'package:smart_meal_management/features/admin/groups/screens/admin_groups_screen.dart';
import 'package:smart_meal_management/features/admin/groups/screens/admin_group_detail_screen.dart';
import 'package:smart_meal_management/features/admin/meals/screens/meal_config_screen.dart';
import 'package:smart_meal_management/features/admin/meals/screens/meal_schedule_screen.dart';
import 'package:smart_meal_management/features/admin/more/screens/admin_more_screen.dart';
import 'package:smart_meal_management/features/admin/profile/screens/admin_profile_screen.dart';
import 'package:smart_meal_management/features/admin/settings/screens/admin_settings_screen.dart';
import 'package:smart_meal_management/features/auth/models/auth_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/features/auth/screens/event_entry_screen.dart';
import 'package:smart_meal_management/features/auth/screens/login_screen.dart';
import 'package:smart_meal_management/features/auth/screens/otp_screen.dart';
import 'package:smart_meal_management/features/auth/screens/role_select_screen.dart';
import 'package:smart_meal_management/features/auth/screens/splash_screen.dart';
import 'package:smart_meal_management/features/auth/screens/student_signup_screen.dart';
import 'package:smart_meal_management/features/auth/screens/admin_signup_screen.dart';
import 'package:smart_meal_management/features/auth/screens/event_admin_signup_screen.dart';
import 'package:smart_meal_management/features/auth/screens/event_guest_join_screen.dart';
import 'package:smart_meal_management/features/auth/screens/forgot_password_screen.dart';
import 'package:smart_meal_management/features/auth/screens/reset_password_screen.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/event_admin_landing_screen.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/event_admin_shell.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/event_create_screen.dart';
import 'package:smart_meal_management/features/events/screens/event_guest/event_guest_shell.dart';
import 'package:smart_meal_management/features/groups/screens/group_join_screen.dart';
import 'package:smart_meal_management/features/student/attendance/screens/attendance_history_screen.dart';
import 'package:smart_meal_management/features/student/attendance/screens/attendance_screen.dart';
import 'package:smart_meal_management/features/student/billing/screens/student_billing_screen.dart';
import 'package:smart_meal_management/features/student/dashboard/screens/student_dashboard_screen.dart';
import 'package:smart_meal_management/features/student/meals/screens/today_meals_screen.dart';
import 'package:smart_meal_management/features/student/meals/screens/weekly_menu_screen.dart';
import 'package:smart_meal_management/features/student/profile/screens/student_profile_screen.dart';
import 'package:smart_meal_management/features/student/settings/screens/student_settings_screen.dart';
import 'package:smart_meal_management/features/student/student_shell.dart';
import 'package:smart_meal_management/shared/screens/not_found_screen.dart';

// buildRouter -----------------------------------------------------------

/// Central routing configuration for the MealAttend SaaS app.
///
/// Auth-reactive routing: [GoRouter.refreshListenable] is wired to
/// [AuthProvider]. Whenever auth state changes GoRouter re-evaluates
/// [redirect] automatically.
///
/// [ShellRoute] wraps student and admin sub-trees so the bottom nav bar
/// persists across tab switches without re-rendering.
///
/// Event admin and event guest live outside the student/admin shells.
/// They use plain [GoRoute]s backed by [EventAdminShell] / [EventGuestShell].
GoRouter buildRouter(AuthProvider auth) {
  final studentNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'student');
  final adminNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'admin');

  bool isAuthRoute(String location) =>
      location == RouteNames.roleSelect ||
      location == RouteNames.splash ||
      location == RouteNames.eventEntry ||
      location == RouteNames.eventGuestJoin ||
      location == RouteNames.login ||
      location == RouteNames.otp ||
      location == RouteNames.studentSignup ||
      location == RouteNames.adminSignup ||
      location == RouteNames.eventSignup;

  bool isProtectedRoute(String location) =>
      location.startsWith('/student') ||
      location.startsWith('/admin') ||
      location.startsWith('/event-admin');
      // Note: /event-guest is intentionally NOT protected — event guests are
      // temporary session users who join without a persistent account.

  String dashboardFor(AuthProvider p) {
    final user = p.currentUser;
    if (user == null) return RouteNames.roleSelect;
    if (user.role.isAdminGroup) return RouteNames.adminDashboard;
    if (user.role == UserRole.eventAdmin) return RouteNames.eventAdminRoot;
    if (user.role == UserRole.eventGuest) return RouteNames.eventGuestJoin;
    return RouteNames.studentDashboard;
  }

  return GoRouter(
    initialLocation: RouteNames.splash,
    refreshListenable: auth,
    errorBuilder: (context, state) => const NotFoundScreen(),

    redirect: (context, state) {
      final location = state.matchedLocation;

      if (auth.state is AuthUnknown) return null;

      final authenticated = auth.isAuthenticated;

      // Unauthenticated on protected route
      if (!authenticated && isProtectedRoute(location) && !isAuthRoute(location)) {
        return RouteNames.roleSelect;
      }

      // Authenticated on auth/entry screen
      if (authenticated && isAuthRoute(location)) {
        return dashboardFor(auth);
      }

      // Authenticated but in wrong role shell
      final user = auth.currentUser;
      if (authenticated && user != null) {
        if (location.startsWith('/admin') && !user.role.isAdminGroup) {
          return dashboardFor(auth);
        }
        if (location.startsWith('/student') && !user.role.isStudentGroup) {
          return dashboardFor(auth);
        }
        if (location.startsWith('/event-admin') && !user.role.isEventGroup) {
          return dashboardFor(auth);
        }
        if (location.startsWith('/event-guest') && !user.role.isEventGroup) {
          return dashboardFor(auth);
        }
      }

      return null;
    },

    routes: [
      // Entry / Splash
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RouteNames.roleSelect,
        builder: (context, state) => const RoleSelectScreen(),
      ),

      // Event entry selection (Admin vs Guest)
      GoRoute(
        path: RouteNames.eventEntry,
        builder: (context, state) => const EventEntryScreen(),
      ),

      // Auth: Login
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) {
          final extra = state.extra;
          // roleContext travels in the URL query (?role=admin) so it survives
          // GoRouter refreshes (refreshListenable: auth) during the login attempt.
          // Without this, a refresh dropped state.extra and the admin login screen
          // flipped to the student ('student' fallback) screen mid-sign-in.
          final roleContext = state.uri.queryParameters['role'] ??
              (extra is AuthRouteExtra ? extra.roleContext : 'student');
          return LoginScreen(roleContext: roleContext);
        },
      ),

      // Auth: Forgot password
      GoRoute(
        path: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // Auth: Reset password (step 2 — carries identifier as extra)
      GoRoute(
        path: RouteNames.resetPassword,
        builder: (context, state) {
          final identifier = state.extra is String
              ? state.extra as String
              : '';
          return ResetPasswordScreen(identifier: identifier);
        },
      ),

      // Auth: OTP verification
      GoRoute(
        path: RouteNames.otp,
        builder: (context, state) {
          final extra = state.extra;
          final identifier = extra is OtpRouteExtra ? extra.identifier : '';
          final roleContext = extra is OtpRouteExtra ? extra.roleContext : 'student';
          return OtpScreen(identifier: identifier, roleContext: roleContext);
        },
      ),

      // Auth: Signup screens
      GoRoute(
        path: RouteNames.studentSignup,
        builder: (context, state) => const StudentSignupScreen(),
      ),
      GoRoute(
        path: RouteNames.adminSignup,
        builder: (context, state) => const AdminSignupScreen(),
      ),
      GoRoute(
        path: RouteNames.eventSignup,
        builder: (context, state) => const EventAdminSignupScreen(),
      ),

      // Event Guest: Join (no account required)
      GoRoute(
        path: RouteNames.eventGuestJoin,
        builder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return EventGuestJoinScreen(initialCode: code);
        },
      ),

      // Groups: Join (navigated to via QR scan or enter-code from NoGroupScreen)
      GoRoute(
        path: RouteNames.groupJoin,
        builder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return GroupJoinScreen(prefillCode: code);
        },
      ),

      // Student shell (bottom nav persists across tabs)
      ShellRoute(
        navigatorKey: studentNavigatorKey,
        builder: (context, state, child) => StudentShell(child: child),
        routes: [
          GoRoute(
            path: RouteNames.studentDashboard,
            builder: (context, state) => const StudentDashboardScreen(),
          ),
          GoRoute(
            path: RouteNames.studentMeals,
            builder: (context, state) => const TodayMealsScreen(),
          ),
          GoRoute(
            path: RouteNames.studentAttendance,
            builder: (context, state) => const AttendanceScreen(),
            routes: [
              GoRoute(
                path: 'history',
                builder: (context, state) => const AttendanceHistoryScreen(),
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.studentWeeklyMenu,
            builder: (context, state) => const WeeklyMenuScreen(),
          ),
          GoRoute(
            path: RouteNames.studentProfile,
            builder: (context, state) => const StudentProfileScreen(),
          ),
          GoRoute(
            path: RouteNames.studentSettings,
            builder: (context, state) => const StudentSettingsScreen(),
          ),
          GoRoute(
            path: RouteNames.studentBilling,
            builder: (context, state) => const StudentBillingScreen(),
          ),
        ],
      ),

      // Admin shell (bottom nav persists across tabs)
      ShellRoute(
        navigatorKey: adminNavigatorKey,
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: RouteNames.adminDashboard,
            builder: (context, state) => const AdminDashboardScreen(),
          ),
          GoRoute(
            path: RouteNames.adminMealConfig,
            builder: (context, state) => const MealConfigScreen(),
            routes: [
              GoRoute(
                path: 'schedule',
                builder: (context, state) => MealScheduleScreen(
                  initialGroupId: state.uri.queryParameters['groupId'],
                  dayWiseMode:
                      state.uri.queryParameters['mode'] == 'daywise',
                ),
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.adminAttendance,
            builder: (context, state) => const AdminAttendanceScreen(),
          ),
          GoRoute(
            path: RouteNames.adminGroups,
            builder: (context, state) => const AdminGroupsScreen(),
            routes: [
              GoRoute(
                path: ':groupId',
                builder: (context, state) {
                  final groupId = state.pathParameters['groupId'] ?? '';
                  // Auth guard in redirect ensures user is non-null here.
                  // Empty string causes the screen to show an empty state.
                  final orgId = auth.currentUser?.organizationId ?? '';
                  return AdminGroupDetailScreen(
                    groupId: groupId,
                    organizationId: orgId,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.adminExports,
            builder: (context, state) => const ExportScreen(),
          ),
          GoRoute(
            path: RouteNames.adminBilling,
            builder: (context, state) => const BillingScreen(),
          ),
          GoRoute(
            path: RouteNames.adminSettings,
            builder: (context, state) => const AdminSettingsScreen(),
          ),
          GoRoute(
            path: RouteNames.adminProfile,
            builder: (context, state) => const AdminProfileScreen(),
          ),
          GoRoute(
            path: RouteNames.adminMore,
            builder: (context, state) => const AdminMoreScreen(),
          ),
          GoRoute(
            path: RouteNames.adminMyAttendance,
            builder: (context, state) => const StaffAttendanceScreen(),
          ),
        ],
      ),

      // ── Event Admin routes ────────────────────────────────────────────────

      // Event Admin: Landing screen — list of admin's events.
      GoRoute(
        path: RouteNames.eventAdminRoot,
        builder: (context, state) => const EventAdminLandingScreen(),
      ),

      // Event Admin: Specific event shell (4-tab).
      GoRoute(
        path: '/event-admin/event/:eventId',
        builder: (context, state) {
          final eventId = state.pathParameters['eventId'];
          if (eventId == null || eventId.isEmpty) {
            return const NotFoundScreen();
          }
          return EventAdminShell(eventId: eventId);
        },
      ),

      // Event Admin: Create new event form.
      GoRoute(
        path: RouteNames.eventAdminCreate,
        builder: (context, state) => const EventCreateScreen(),
      ),

      // Legacy redirect — keeps old deep-links functional.
      GoRoute(
        path: RouteNames.eventAdminDashboard,
        redirect: (context, state) {
          final eventId = state.uri.queryParameters['eventId'];
          if (eventId != null && eventId.isNotEmpty) {
            return '/event-admin/event/$eventId';
          }
          return RouteNames.eventAdminRoot;
        },
      ),

      // Event Guest (shell — receives party data via GoRouter extra or QR code)
      GoRoute(
        path: RouteNames.eventGuestDashboard,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is EventGuestJoinExtra) {
            return EventGuestShell(joinExtra: extra);
          }
          final code = state.uri.queryParameters['code'];
          return EventGuestShell(joinCode: code);
        },
      ),
    ],
  );
}

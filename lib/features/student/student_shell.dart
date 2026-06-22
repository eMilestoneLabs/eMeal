import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_bottom_nav_bar.dart';

/// Persistent shell for the student/member role.
///
/// ## Tab set (dynamic — 2–5 tabs)
///
/// The visible tabs depend on two signals:
/// 1. **Group membership** — if [user.groupIds] is empty only Home + Profile
///    are shown (the other tabs require an active group).
/// 2. **[GroupMealConfig]** — once the student loads their group config the
///    shell rebuilds its nav. Meals tab hides when `mealsEnabled = false`;
///    Weekly Menu tab hides when `weeklyMenuEnabled = false`.
///
/// [GroupConfigProvider] is created here and injected into descendants via
/// [GroupConfigScope]. [StudentDashboardProvider] calls
/// `GroupConfigProvider.update()` after fetching the group, which triggers
/// this shell to rebuild its nav bar with the correct tab count.
class StudentShell extends StatefulWidget {
  const StudentShell({super.key, required this.child});

  /// The currently active tab's screen, provided by [ShellRoute].
  final Widget child;

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  // ── GroupConfigProvider — created here, injected via GroupConfigScope ──────
  late final GroupConfigProvider _groupConfig;

  // ── StudentDashboardProvider — shared across all student tabs ─────────────
  //
  // Creating it here ensures that switching between Home and Meals tabs does
  // not tear down and re-create the provider (and re-fire 5 parallel API calls).
  // The actual initial load() is still triggered by StudentDashboardScreen once
  // the auth context is available.
  late final StudentDashboardProvider _dashboardProvider;

  // ── Full tab + route catalogue ─────────────────────────────────────────────
  //
  // Tabs are assembled at build time based on membership + config.

  static const _homeTab = AppNavBarItem(
    label: 'Home',
    icon: Icons.home_outlined,
    activeIcon: Icons.home_rounded,
  );
  static const _mealsTab = AppNavBarItem(
    label: 'Meals',
    icon: Icons.restaurant_outlined,
    activeIcon: Icons.restaurant_rounded,
  );
  static const _attendanceTab = AppNavBarItem(
    label: 'Attendance',
    icon: Icons.check_circle_outline_rounded,
    activeIcon: Icons.check_circle_rounded,
  );
  static const _menuTab = AppNavBarItem(
    label: 'Menu',
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book_rounded,
  );
  static const _profileTab = AppNavBarItem(
    label: 'Profile',
    icon: Icons.person_outline_rounded,
    activeIcon: Icons.person_rounded,
  );

  // ── Minimal tab set (no group joined) ─────────────────────────────────────

  static const _minimalItems = [_homeTab, _profileTab];
  static const _minimalRoutes = [
    RouteNames.studentDashboard,
    RouteNames.studentProfile,
  ];

  @override
  void initState() {
    super.initState();
    _groupConfig = GroupConfigProvider();
    // Pass the shell-level GroupConfigProvider so the dashboard can push
    // tab-visibility updates (meals enabled, weekly menu enabled) to the shell.
    _dashboardProvider = StudentDashboardProvider(
      groupConfigProvider: _groupConfig,
    );
  }

  @override
  void dispose() {
    _dashboardProvider.dispose();
    _groupConfig.dispose();
    super.dispose();
  }

  // ── Dynamic tab builder ────────────────────────────────────────────────────

  /// Builds the tab list based on group membership + meal config.
  ///
  /// Rules:
  /// - No group → [_minimalItems] (Home + Profile only)
  /// - Has group + mealsEnabled=false → Home, Attendance, Profile (3 tabs)
  /// - Has group + mealsEnabled=true + weeklyMenuEnabled=false → Home, Meals,
  ///   Attendance, Profile (4 tabs)
  /// - Has group + mealsEnabled=true + weeklyMenuEnabled=true → all 5 tabs
  List<AppNavBarItem> _buildTabs(bool hasGroup) {
    if (!hasGroup) return _minimalItems;
    if (!_groupConfig.mealsEnabled) {
      // Meals disabled — meals + menu both hidden; 3 tabs
      return [_homeTab, _attendanceTab, _profileTab];
    }
    if (!_groupConfig.weeklyMenuEnabled ||
        _groupConfig.dayWiseMealsEnabled) {
      // Meals on, but no weekly menu — 4 tabs
      return [_homeTab, _mealsTab, _attendanceTab, _profileTab];
    }
    // Full 5-tab set
    return [_homeTab, _mealsTab, _attendanceTab, _menuTab, _profileTab];
  }

  List<String> _buildRoutes(bool hasGroup) {
    if (!hasGroup) return _minimalRoutes;
    if (!_groupConfig.mealsEnabled) {
      return [
        RouteNames.studentDashboard,
        RouteNames.studentAttendance,
        RouteNames.studentProfile,
      ];
    }
    if (!_groupConfig.weeklyMenuEnabled ||
        _groupConfig.dayWiseMealsEnabled) {
      return [
        RouteNames.studentDashboard,
        RouteNames.studentMeals,
        RouteNames.studentAttendance,
        RouteNames.studentProfile,
      ];
    }
    return [
      RouteNames.studentDashboard,
      RouteNames.studentMeals,
      RouteNames.studentAttendance,
      RouteNames.studentWeeklyMenu,
      RouteNames.studentProfile,
    ];
  }

  // ── Index helpers ──────────────────────────────────────────────────────────

  int _currentIndex = 0;

  int _indexFromLocation(String location, List<String> routes) {
    for (int i = routes.length - 1; i >= 0; i--) {
      if (location.startsWith(routes[i])) return i;
    }
    return 0;
  }

  void _onTap(BuildContext context, int index, List<String> routes) {
    // Always call context.go — do NOT early-return when index == _currentIndex.
    // Reason: non-tab routes (e.g. /student/settings) resolve to index 0 via
    // _indexFromLocation, so tapping Home while on Settings would bail early
    // and leave the user stranded on Settings.
    setState(() => _currentIndex = index);
    context.go(routes[index]);
    // Issue 4: returning to the Home tab reloads the dashboard so an attendance
    // mark made on another tab is reflected immediately (the action card flips
    // to the submitted status instead of still prompting "Mark Present").
    if (index == 0) {
      final user = AuthProviderScope.of(context).currentUser;
      if (user != null) {
        _dashboardProvider.load(user: user);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = AuthProviderScope.of(context).currentUser;
    final hasGroup = user?.effectiveGroupIds.isNotEmpty ?? false;
    final routes = _buildRoutes(hasGroup);
    final location = GoRouterState.of(context).uri.toString();
    final derived = _indexFromLocation(location, routes);
    if (derived != _currentIndex) {
      setState(() => _currentIndex = derived);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StudentDashboardScope(
      notifier: _dashboardProvider,
      child: GroupConfigScope(
      notifier: _groupConfig,
      child: ListenableBuilder(
        // Listen to both auth (group joins/leaves) and meal config updates.
        listenable: Listenable.merge([
          AuthProviderScope.of(context),
          _groupConfig,
        ]),
        builder: (context, _) {
          final user = AuthProviderScope.of(context).currentUser;
          final hasGroup = user?.effectiveGroupIds.isNotEmpty ?? false;
          final tabs = _buildTabs(hasGroup);
          final routes = _buildRoutes(hasGroup);

          // Clamp index in case the tab set shrinks (e.g., meals disabled by admin,
          // or student group revoked) — avoids out-of-range crash.
          final safeIndex = _currentIndex.clamp(0, tabs.length - 1);
          if (safeIndex != _currentIndex) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _currentIndex = safeIndex),
            );
          }

          return Scaffold(
            body: widget.child,
            bottomNavigationBar: AppBottomNavBar(
              items: tabs,
              currentIndex: safeIndex,
              onTap: (i) => _onTap(context, i, routes),
            ),
          );
        },
      ),
      ),
    );
  }
}

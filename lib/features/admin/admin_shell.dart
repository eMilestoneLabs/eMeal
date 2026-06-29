import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/data/services/cache_warmer.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_bottom_nav_bar.dart';

/// Persistent shell for admin/manager roles.
///
/// Wraps all admin routes in a [Scaffold] with a shared [AppBottomNavBar].
/// Uses [IndexedStack] semantics via GoRouter's [ShellRoute] — the [child]
/// parameter is the currently active tab's screen.
///
/// Tabs (in order):
///   0 — Home / Dashboard
///   1 — Groups
///   2 — Meals (configuration)
///   3 — Attendance (management)
///   4 — More (Profile / Settings / Exports)
class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.child});

  /// The currently active tab's screen, provided by [ShellRoute].
  final Widget child;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static const _tabs = [
    AppNavBarItem(
      label: 'Home',
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard_rounded,
    ),
    AppNavBarItem(
      label: 'Groups',
      icon: Icons.group_outlined,
      activeIcon: Icons.group_rounded,
    ),
    AppNavBarItem(
      label: 'Meals',
      icon: Icons.restaurant_menu_outlined,
      activeIcon: Icons.restaurant_menu_rounded,
    ),
    AppNavBarItem(
      label: 'Attendance',
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check_rounded,
    ),
    AppNavBarItem(
      label: 'More',
      icon: Icons.more_horiz_outlined,
      activeIcon: Icons.more_horiz_rounded,
    ),
  ];

  /// Maps tab index → the canonical route path for that tab.
  static const _tabRoutes = [
    RouteNames.adminDashboard,   // 0 — Home
    RouteNames.adminGroups,      // 1 — Groups
    RouteNames.adminMealConfig,  // 2 — Meals
    RouteNames.adminAttendance,  // 3 — Attendance
    RouteNames.adminMore,        // 4 — More
  ];

  int _currentIndex = 0;

  /// Shell-owned dashboard provider — hoisted here (not created per-screen) so
  /// its in-memory state survives tab switches and the Home tab never flashes
  /// zeros on return (Issue 1). Disposed with the shell (i.e. on logout).
  late final AdminDashboardProvider _dashboardProvider;

  /// Sub-routes pushed from the "More" hub all map to tab 4.
  static const _moreSubRoutes = [
    RouteNames.adminProfile,
    RouteNames.adminSettings,
    RouteNames.adminExports,
  ];

  /// Derives the active tab index from the current GoRouter location so the
  /// correct tab is highlighted on deep-link or programmatic navigation.
  ///
  /// Sub-routes of the More hub (/admin/profile, /admin/settings,
  /// /admin/exports) are checked first so they resolve to tab 4 even though
  /// they do not start with /admin/more.
  int _indexFromLocation(String location) {
    if (_moreSubRoutes.any((r) => location.startsWith(r))) return 4;
    for (int i = _tabRoutes.length - 1; i >= 0; i--) {
      if (location.startsWith(_tabRoutes[i])) return i;
    }
    return 0;
  }

  /// Handles bottom-nav taps.
  ///
  /// Always calls [context.go] — even when re-tapping the active tab —
  /// so any pushed sub-routes (Profile, Settings, Exports) are popped
  /// and the shell returns to the tab's root screen.
  void _onTap(BuildContext context, int index) {
    setState(() => _currentIndex = index);
    context.go(_tabRoutes[index]);
  }

  @override
  void initState() {
    super.initState();
    _dashboardProvider = AdminDashboardProvider();
  }

  @override
  void dispose() {
    _dashboardProvider.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Warm the non-landing tabs' caches once per account (self-guarded), so the
    // first open of Groups/Meals/Attendance is an instant cache hit instead of
    // a cold network fetch. Fire-and-forget; never blocks the UI.
    final user = AuthProviderScope.of(context).currentUser;
    if (user != null) {
      CacheWarmer.instance.warmAdmin(user);
    }
    final location = GoRouterState.of(context).uri.toString();
    final derived = _indexFromLocation(location);
    if (derived != _currentIndex) {
      setState(() => _currentIndex = derived);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminDashboardScope(
      notifier: _dashboardProvider,
      child: Scaffold(
        body: widget.child,
        bottomNavigationBar: AppBottomNavBar(
          items: _tabs,
          currentIndex: _currentIndex,
          onTap: (i) => _onTap(context, i),
        ),
      ),
    );
  }
}
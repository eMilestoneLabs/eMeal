import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/realtime_events.dart';
import 'package:smart_meal_management/data/services/cache_warmer.dart';
import 'package:smart_meal_management/data/services/realtime_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_bottom_nav_bar.dart';
import 'package:smart_meal_management/shared/widgets/shell_back_handler.dart';

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

class _StudentShellState extends State<StudentShell>
    with WidgetsBindingObserver {
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

  // ── Live-Test-17 JOIN-01: membership reconciliation ───────────────────────
  //
  // Admin approval is an AUTHORITATIVE server-side transition that must land on
  // the member's already-open app — no Profile→Home, no restart, no re-login.
  // Owned by the SHELL (not a screen) because the screen that is stuck is
  // `NoGroupScreen`, and the same stale state is reachable from the Attendance
  // tab; a screen-scoped listener would only reconcile while that one screen
  // happened to be mounted.
  StreamSubscription<RealtimeMessage>? _rtSub;

  /// Single-flight guard. The server emits to `group:{id}` AND `user:{id}`, so
  /// a socket in both rooms receives the frame twice — and `refreshSession`
  /// ROTATES the refresh token, where two concurrent calls would land on the
  /// theft-detection reuse path. One reconcile at a time, always.
  bool _reconcilingJoin = false;

  /// Captured in [didChangeDependencies] so the realtime callback never has to
  /// touch an InheritedWidget outside of build.
  AuthProvider? _auth;

  @override
  void initState() {
    super.initState();
    _groupConfig = GroupConfigProvider();
    // Pass the shell-level GroupConfigProvider so the dashboard can push
    // tab-visibility updates (meals enabled, weekly menu enabled) to the shell.
    _dashboardProvider = StudentDashboardProvider(
      groupConfigProvider: _groupConfig,
    );
    // The socket is already open (AuthProvider connects on login/restore) and
    // the gateway auto-joins `user:{id}`, so this needs no room management.
    _rtSub = RealtimeService.instance
        .on(RealtimeEvents.groupMemberUpdated)
        .listen(_onMembershipEvent);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Realtime alone CANNOT cover approval — and this is the most common real
  /// sequence, not an edge case.
  ///
  /// `RealtimeService` deliberately tears the socket DOWN while the app is
  /// backgrounded (battery). Socket.IO does not replay frames to a disposed
  /// client, so an approval that happens while the member is waiting with the
  /// app in the background is lost permanently: on resume the socket
  /// reconnects, no event arrives, and the member is still looking at
  /// "You haven't joined a group yet".
  ///
  /// Cost is deliberately zero for everyone else: the probe only runs while the
  /// member has NO group — i.e. exactly the stuck state. A member who already
  /// belongs to a group performs no extra work on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted || _reconcilingJoin) return;
    final user = _auth?.currentUser;
    if (user == null || user.effectiveGroupIds.isNotEmpty) return;
    unawaited(_reconcileMembership());
  }

  /// Reconciles an approved join onto the live app.
  ///
  /// Deliberately does THREE things in order — doing fewer is a regression:
  ///   1. `refreshSession()` ONLY when the org claim is missing. A first-time
  ///      joiner signs up with no organization; approval sets it in the DB but
  ///      the JWT still carries the old null claim, and `organizationId` is
  ///      read from the JWT alone. Skipping this leaves every org-scoped call
  ///      failing. Gating it on `isEmpty` keeps token rotation to once per
  ///      member lifetime instead of once per membership event.
  ///   2. `refreshCurrentUser()` — brings `groupIds` in, which flips the
  ///      no-group gate and the shell's tab set.
  ///   3. `load()` — MANDATORY. `StudentDashboardScreen.didChangeDependencies`
  ///      is one-shot and the screen is ALREADY mounted, so nothing else would
  ///      ever fire the first group-scoped load. Without it the member trades a
  ///      correct "you haven't joined a group yet" screen for a hollow
  ///      dashboard (no group name, no meals, no summary, no loader) AND a
  ///      3-tab nav, because an unloaded GroupMealConfig defaults to
  ///      Attendance-Only.
  Future<void> _onMembershipEvent(RealtimeMessage msg) async {
    if (!mounted || _reconcilingJoin) return;
    if (msg.data['action'] != 'joined') return;

    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null) return;
    // User isolation: only ever react to THIS account's membership.
    if (msg.data['userId']?.toString() != user.id) return;
    final groupId = msg.data['groupId']?.toString();
    if (groupId == null || groupId.isEmpty) return;
    // Already known — nothing to reconcile (covers the duplicate delivery).
    if (user.effectiveGroupIds.contains(groupId)) return;

    await _reconcileMembership();
  }

  /// The single reconcile path, shared by the realtime event and the
  /// resume probe so the two can never drift apart.
  Future<void> _reconcileMembership() async {
    final auth = _auth;
    final user = auth?.currentUser;
    if (auth == null || user == null || _reconcilingJoin) return;

    _reconcilingJoin = true;
    try {
      if (user.organizationId.isEmpty) {
        await auth.refreshSession();
      }
      await auth.refreshCurrentUser();
      if (!mounted) return;
      final refreshed = auth.currentUser;
      if (refreshed != null && refreshed.effectiveGroupIds.isNotEmpty) {
        await _dashboardProvider.load(user: refreshed);
      }
    } catch (_) {
      // Fail-soft: a failed reconcile must never break the running app. The
      // member keeps the pre-existing manual paths (pull-to-refresh, tab
      // switch) and the next event or app resume retries.
    } finally {
      _reconcilingJoin = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rtSub?.cancel();
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

  /// Current router location, captured in [didChangeDependencies] (where it is
  /// already read) so the back handler costs no extra lookup.
  ///
  /// Live-Test-16 ISSUE-2: the back policy MUST key off this and not off
  /// [_currentIndex] — [_indexFromLocation] returns 0 for every non-tab path
  /// (`/student/settings`, `/student/billing`), so an index-based test would
  /// mistake those screens for Home and close the app. Starts empty, which
  /// reads as "not home" — the fail-safe direction (go home, never exit).
  String _location = '';

  bool get _isHomeLocation =>
      isShellHomeLocation(_location, RouteNames.studentDashboard);

  /// Back-to-Home routed through the SAME handler as a Home tab tap, so the
  /// dashboard refresh in [_onTap] is not skipped.
  void _goHome() {
    final user = AuthProviderScope.of(context).currentUser;
    final hasGroup = user?.effectiveGroupIds.isNotEmpty ?? false;
    _onTap(context, 0, _buildRoutes(hasGroup));
  }

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
    final auth = AuthProviderScope.of(context);
    _auth = auth; // JOIN-01: used by the realtime reconciler (no build context)
    final user = auth.currentUser;
    // Warm the non-landing tabs' caches once per account (self-guarded), so the
    // first open of Attendance/Profile/Groups is an instant cache hit instead
    // of a cold network fetch. Fire-and-forget; never blocks the UI.
    if (user != null) {
      CacheWarmer.instance.warmStudent(user, auth: auth);
    }
    final hasGroup = user?.effectiveGroupIds.isNotEmpty ?? false;
    final routes = _buildRoutes(hasGroup);
    final location = GoRouterState.of(context).uri.toString();
    _location = location;
    final derived = _indexFromLocation(location, routes);
    if (derived != _currentIndex) {
      setState(() => _currentIndex = derived);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live-Test-16 ISSUE-2: sits OUTSIDE the ListenableBuilder so it never
    // rebuilds — `canPop` is constant and the state is read lazily in the
    // callback. Only consulted when nothing is left to pop.
    return ShellBackHandler(
      isHome: () => _isHomeLocation,
      onGoHome: _goHome,
      child: StudentDashboardScope(
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
      ),
    );
  }
}

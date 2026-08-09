import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/data/services/group_order_service.dart';
import 'package:smart_meal_management/features/notices/widgets/notice_bell.dart';
import 'package:smart_meal_management/features/groups/screens/group_detail_screen.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/features/student/dashboard/screens/no_group_screen.dart';
import 'package:smart_meal_management/features/student/dashboard/widgets/meal_timeline_card.dart';
import 'package:smart_meal_management/features/student/dashboard/widgets/open_now_carousel.dart';
import 'package:smart_meal_management/features/student/dashboard/widgets/student_greeting_card.dart';
// group_config_provider.dart removed — GroupConfigProvider is now managed by
// StudentShell and accessed only via StudentDashboardProvider.
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/utils/verification_gate.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/features/student/meals/screens/meal_detail_screen.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';
import 'package:smart_meal_management/shared/widgets/app_glass_card.dart';
import 'package:smart_meal_management/shared/widgets/app_screen_states.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Formats an approved vacation as "22 Jun → 30 Jun" for the dashboard badge.
/// Returns null when there is no active vacation.
String? _vacationRangeLabel(VacationRequestModel? v) {
  if (v == null) return null;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String f(DateTime d) => '${d.day} ${months[d.month - 1]}';
  return '${f(v.startDate)} → ${f(v.endDate)}';
}

/// Primary student dashboard — the home tab of the student shell.
///
/// ## Layout (scrollable)
/// ```
/// [greeting card]
/// ─── Vacation mode banner (conditional) ───
/// [next / current meal card]
/// [section: Today's Meals]
/// [meal timeline horizontal scroll]
/// [section: 30-Day Summary]
/// [attendance summary bar]
/// ```
///
/// State is managed by [StudentDashboardProvider] (ChangeNotifier).
/// The provider is created once inside [State] and disposed with it.
class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  // Provider is now owned by the shell (StudentDashboardScope) — this screen
  // reads it from the scope and fires the initial load if not yet done.
  AuthProvider? _authProvider;
  bool _initialized = false;

  // ISSUE-001: the active group now lives centrally in AuthProvider — every
  // group-scoped screen reads it via currentUser.groupId, so a switch here
  // propagates to attendance/billing/menu/notices/profile automatically.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    // Listen to auth changes (vacation toggle, default attendance from settings)
    // so the dashboard reflects them immediately without requiring a full reload.
    _authProvider = AuthProviderScope.of(context);
    _authProvider!.addListener(_onUserChanged);

    // Reflect server-driven user changes (e.g. an admin approving a vacation
    // request flips isVacationMode ON) without an app restart — the banner +
    // greeting read currentUser.isVacationMode live and rebuild via the listener.
    _authProvider!.refreshCurrentUser();

    // Trigger initial load via the shell-level shared provider.
    final provider = StudentDashboardScope.of(context);
    final user = _authProvider!.currentUser;
    if (user != null && !provider.isLoading && provider.todayMeals.isEmpty) {
      provider.load(user: _userWithActiveGroup(user));
    }
  }

  /// The auth-effective user — [AuthProvider.currentUser] already applies the
  /// active group override (ISSUE-001), so no per-screen patching is needed.
  UserModel _userWithActiveGroup(UserModel user) => user;

  /// ISSUE 2: open the read-only group details page for the active group.
  void _openGroupDetails(String groupId, String organizationId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupDetailScreen(
          groupId: groupId,
          organizationId: organizationId,
        ),
      ),
    );
  }

  /// Switches the active group centrally (ISSUE-001) and reloads all data.
  ///
  /// [AuthProvider.setActiveGroup] notifies the whole tree — the shell
  /// rebuilds its tabs for the new group's config, and every group-scoped
  /// screen re-reads `currentUser.groupId` (SWR caches are group-keyed, so no
  /// stale cross-group paint is possible). The dashboard reloads immediately.
  Future<void> _switchGroup(String groupId) async {
    final auth = _authProvider;
    if (auth == null) return;
    final current = auth.currentUser?.groupId;
    if (current == groupId) return;
    // Capture before the awaits — no BuildContext across async gaps.
    final provider = StudentDashboardScope.of(context);
    await auth.setActiveGroup(groupId);
    final user = auth.currentUser;
    if (user != null) {
      await provider.load(user: user);
    }
  }

  /// Fires when vacation mode or other user flags change from settings screen.
  ///
  /// Syncs vacation state into the dashboard provider and reschedules local
  /// notifications immediately when vacation turns OFF.
  void _onUserChanged() {
    final user = _authProvider?.currentUser;
    if (user == null || !mounted) return;
    final p = StudentDashboardScope.maybeOf(context);
    if (p == null) return;

    final wasVacation = p.isVacationMode;
    p.setVacationMode(user.isVacationMode);

    // Reschedule reminders immediately when vacation ends.
    if (wasVacation && !user.isVacationMode && p.remindersEnabled && p.todayMeals.isNotEmpty) {
      NotificationService.instance.syncReminders(
        p.todayMeals,
        isVacationMode: false,
        markedMealIds: p.markedMealIds,
      );
    }
  }

  @override
  void dispose() {
    _authProvider?.removeListener(_onUserChanged);
    // Do NOT dispose the provider — it is owned by StudentShell.
    super.dispose();
  }

  Future<void> _onRefresh() async {
    final auth = AuthProviderScope.of(context);
    // Capture the shared provider BEFORE the await so we never touch
    // BuildContext across an async gap (use_build_context_synchronously).
    final provider = StudentDashboardScope.of(context);
    // Pull-to-refresh also re-syncs the user so an approved vacation (or an
    // early return) is reflected immediately.
    await auth.refreshCurrentUser();
    final user = auth.currentUser;
    if (user != null) {
      await provider.load(user: _userWithActiveGroup(user));
    }
  }

  /// Issue 3: open the Meal Detail screen (name, menu, attendance window,
  /// preference info) for a tapped today-meal card. Builds a DayMealEntry from
  /// the overlaid MealModel so the per-day menu/window/preference are shown.
  void _openMealDetail(
    BuildContext context,
    MealModel meal,
    AttendanceStatus? status,
  ) {
    final statusLabel = switch (status) {
      AttendanceStatus.present => 'Present',
      AttendanceStatus.absent => 'Absent',
      AttendanceStatus.skipped => 'Skipped',
      _ => null,
    };
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MealDetailScreen(
          entry: DayMealEntry(
            mealId: meal.id,
            name: meal.name,
            slotKey: meal.slotKey,
            order: meal.order,
            menuItems: meal.menuItems,
            imageUrl: meal.imageUrl,
            description: meal.description,
            openTime: meal.attendanceWindow.openTime,
            closeTime: meal.attendanceWindow.closeTime,
            preferencesEnabled: meal.preferencesEnabled,
            enabledPreferences: meal.enabledPreferences,
          ),
          isToday: true,
          statusLabel: statusLabel,
        ),
      ),
    );
  }

  /// Issue #1: marks the current meal Present directly from the dashboard.
  /// If the group requires a meal preference, routes to the attendance screen
  /// so the student can choose a tag (Issue #6) instead of marking blindly.
  Future<void> _markPresentFromDashboard(
    StudentDashboardProvider provider,
    MealModel meal,
  ) async {
    // Live-Test-9 ISSUE-003: the meal card from /meals/today IS the published
    // day-effective truth — when the published day disables preferences the
    // old `|| group-level` OR still forced the preference detour. The group
    // list only fills in TAGS for legacy meals that are enabled without their
    // own. Preference-GROUP meals (day-narrowed by the backend) always route
    // so the member completes each group on the attendance screen.
    final requiresPreference = meal.preferenceGroups.isNotEmpty ||
        (meal.preferencesEnabled &&
            (meal.enabledPreferences.isNotEmpty ||
                provider.enabledPreferences.isNotEmpty));
    if (requiresPreference) {
      context.go(RouteNames.studentAttendance);
      return;
    }
    final user = _authProvider?.currentUser;
    if (user == null) return;
    final ok = await provider.markStatus(
      user: _userWithActiveGroup(user),
      meal: meal,
      status: AttendanceStatus.present,
    );
    if (!mounted) return;
    if (!ok) {
      // SRS Module 03 ACC-005: unverified members get the guided verify flow.
      if (await VerificationGate.handleMessage(context, provider.actionError,
          email: user.email)) {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.actionError ?? 'Could not mark attendance'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Issue #1 + SRS Module 03 (survey Q17/Q21): marks the member ABSENT for
  /// the current meal directly from the dashboard — the member's deliberate
  /// not-eating choice. Skip is an internal system status, never a button.
  Future<void> _skipFromDashboard(
    StudentDashboardProvider provider,
    MealModel meal,
  ) async {
    final user = _authProvider?.currentUser;
    if (user == null) return;
    final ok = await provider.markStatus(
      user: _userWithActiveGroup(user),
      meal: meal,
      status: AttendanceStatus.absent,
    );
    if (!mounted) return;
    if (!ok) {
      // SRS Module 03 ACC-005: unverified members get the guided verify flow.
      if (await VerificationGate.handleMessage(context, provider.actionError,
          email: user.email)) {
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not update attendance'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = StudentDashboardScope.maybeOf(context);
    if (provider == null) {
      return const Scaffold(body: AppDashboardSkeleton());
    }

    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final user = AuthProviderScope.of(context).currentUser;

        // ── No-group gate ──────────────────────────────────────────────────
        // If the user has not joined any group yet, skip all dashboard content
        // and show the premium onboarding prompt instead.
        if (user != null && user.effectiveGroupIds.isEmpty) {
          return const NoGroupScreen();
        }

        final currentUser = user ?? _placeholderUser;

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _onRefresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Top padding ──────────────────────────────────────────
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppConstants.space24)),

                  // ── Notice bell row ──────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      // #9: align to the same 20px margin as the hero card and
                      // every other section so the layout reads as one justified
                      // column (was space12 + an extra inner space8 offset).
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.space20),
                      child: Row(
                        children: [
                          // Pass 13 (FR-OFF-006): "Updated X ago" while the
                          // screen is painting stale cache; disappears the
                          // moment the silent refresh lands.
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FreshnessBadge(
                                  lastUpdated: provider.lastUpdated),
                            ),
                          ),
                          // command_3: always-visible Notepad entry in the
                          // dashboard header (also in Quick Actions + Settings).
                          IconButton(
                            tooltip: 'Notepad',
                            icon: const Icon(Icons.edit_note_rounded),
                            onPressed: () =>
                                context.push(RouteNames.notepad),
                          ),
                          // ISSUE 2: always-visible entry point to the read-only
                          // group details page (info, admin, role, QR, Leave).
                          if (currentUser.groupId != null)
                            IconButton(
                              tooltip: 'Group details',
                              icon: const Icon(Icons.info_outline_rounded),
                              onPressed: () => _openGroupDetails(
                                currentUser.groupId!,
                                currentUser.organizationId,
                              ),
                            ),
                          NoticeBell(
                            organizationId: currentUser.organizationId,
                            groupId: currentUser.groupId,
                            isAdmin: false,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Greeting card ────────────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.space20),
                      child: StudentGreetingCard(
                        user: currentUser,
                        // Use real group name from provider (loaded from mock data)
                        groupName: provider.groupName.isNotEmpty
                            ? provider.groupName
                            : null,
                        // #2: the member's chosen per-group role (e.g. Member).
                        roleLabel: provider.functionalRole.isNotEmpty
                            ? provider.functionalRole
                            : null,
                        streakDays: provider.streakDays,
                        isVacationMode: currentUser.isVacationMode,
                        attendanceRate:
                            provider.summary?.attendanceRate ?? 0.0,
                        isDefaultAttendance: currentUser.isDefaultAttendance,
                        onAvatarTap: () =>
                            context.go(RouteNames.studentProfile),
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppConstants.space16)),

                  // ── Group switcher (multi-group only) ────────────────────
                  if (currentUser.effectiveGroupIds.length > 1)
                    SliverToBoxAdapter(
                      child: _GroupSwitcherRow(
                        groupIds: currentUser.effectiveGroupIds,
                        // ISSUE-001: real group names for chip labels.
                        groupBriefs: currentUser.groups,
                        activeGroupId: currentUser.groupId ??
                            currentUser.effectiveGroupIds.first,
                        onSwitch: _switchGroup,
                        onJoinAnother: () =>
                            context.push(RouteNames.groupJoin),
                        isDark: Theme.of(context).brightness == Brightness.dark,
                      ),
                    ),

                  if (currentUser.effectiveGroupIds.length > 1)
                    const SliverToBoxAdapter(
                        child: SizedBox(height: AppConstants.space16)),

                  // ── Vacation mode banner ─────────────────────────────────
                  // Always read from the live user model (reflects settings
                  // changes immediately via the InheritedNotifier rebuild).
                  if (currentUser.isVacationMode)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.space20),
                        child: _VacationBanner(
                          dateRange: _vacationRangeLabel(provider.activeVacation),
                          // Live-Test-16 ISSUE-2: push, not go. Settings is a
                          // LEAF, not a tab — `go` replaced the shell's only
                          // page, so it rendered with no back arrow
                          // (automaticallyImplyLeading saw an unpoppable
                          // navigator) and Android back closed the app. The
                          // other two entry points to this same screen
                          // (Today's Meals, Profile) already push.
                          onDisable: () =>
                              context.push(RouteNames.studentSettings),
                        ),
                      ),
                    ),

                  if (currentUser.isVacationMode)
                    const SliverToBoxAdapter(
                        child: SizedBox(height: AppConstants.space16)),

                  // ── Loading / Error / Content ────────────────────────────
                  if (provider.isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _LoadingView(),
                    )
                  else if (provider.error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _ErrorView(
                        message: provider.error!,
                        onRetry: _onRefresh,
                      ),
                    )
                  else ...[
                    // ── Partial-failure banner (Pass 13, FR-OFF-012) ─────
                    // Some sections failed while others loaded: render the
                    // parts we have and give a scoped retry — never a blank
                    // screen over data we already hold.
                    if (provider.sectionError != null) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.space20),
                          child: AppSectionError(
                            label: provider.sectionError!,
                            onRetry: _onRefresh,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space16)),
                    ],

                    // ── Open Now carousel (Feature 3) ────────────────────
                    // Multi-card pager: auto-scrolls when all open meals are
                    // marked, otherwise parks on the first pending meal to force
                    // attention. Falls back to a single card when only one meal
                    // qualifies (same look as the original hero card).
                    if (provider.mealsEnabled &&
                        provider.openNowMeals.isNotEmpty)
                      SliverToBoxAdapter(
                        // #3: inset the carousel to the SAME horizontal margin as
                        // the greeting card (space20) so the "Open Now" card edges
                        // line up with the welcome card above instead of running
                        // full-bleed. Padding is symmetric → responsive on any
                        // width; the card fills the inset area.
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.space20),
                          child: OpenNowCarousel(
                          meals: provider.openNowMeals,
                          pendingIndex: provider.firstPendingOpenIndex,
                          statusOf: (m) => provider.statusForMeal(m.id),
                          // Live-Test-9 ISSUE-4.1: marked cards keep showing
                          // the submitted preferences, group-wise.
                          recordOf: (m) => provider.recordForMeal(m.id),
                          isWindowOpen: provider.isWindowOpen,
                          isWindowPast: provider.isWindowPast,
                          // Issue #1: mark in place so the card flips to Present.
                          // When preferences are required, _markPresentFromDashboard
                          // routes to the attendance screen so a tag is picked first.
                          onMarkPresent: (m) =>
                              _markPresentFromDashboard(provider, m),
                          onSkip: (m) => _skipFromDashboard(provider, m),
                          onMarkAttendance: (m) =>
                              context.go(RouteNames.studentAttendance),
                          // Issue 3: tap a carousel card to open meal details.
                          onTapMeal: (m) => _openMealDetail(
                              context, m, provider.statusForMeal(m.id)),
                          ),
                        ),
                      ),

                    if (provider.mealsEnabled &&
                        provider.openNowMeals.isNotEmpty)
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space24)),

                    // ── Today's Meals section ────────────────────────────
                    if (provider.mealsEnabled &&
                        provider.todayMeals.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: "Today's Meals",
                          actionLabel: provider.weeklyMenuEnabled
                              ? 'Full Menu'
                              : null,
                          onAction: provider.weeklyMenuEnabled
                              ? () =>
                                  context.go(RouteNames.studentWeeklyMenu)
                              : null,
                        ),
                      ),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space12)),
                      SliverToBoxAdapter(
                        child: MealTimelineCard(
                          meals: provider.todayMeals,
                          provider: provider,
                          onMealTap: (meal) => _openMealDetail(
                              context, meal, provider.statusForMeal(meal.id)),
                        ),
                      ),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space24)),
                    ],

                    // ── No meal today (SRS FR-MODE-032 / LOOP-094) ───────
                    // Planner mode with no published meal for today = holiday
                    // or off-day: explicit state, nothing markable or billed.
                    if (provider.mealsEnabled &&
                        !provider.isLoading &&
                        provider.todayMeals.isEmpty &&
                        (provider.groupConfig.weeklyMenuEnabled ||
                            provider.groupConfig.dayWiseMealsEnabled)) ...[
                      const SliverToBoxAdapter(child: _NoMealTodayCard()),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space24)),
                    ],

                    // ── 30-Day Attendance Summary ─────────────────────────
                    if (provider.summary != null) ...[
                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: '30-Day Summary',
                          actionLabel: 'History',
                          // Live-Test-16 ISSUE-2: push, not go. `go` built the
                          // whole `/student/attendance/history` match stack, so
                          // back landed on the Attendance TAB rather than
                          // returning here — and it constructed AttendanceScreen
                          // needlessly. History depends only on
                          // AuthProviderScope (shell-level), so pushing it
                          // alone is both correct and one screen cheaper.
                          onAction: () =>
                              context.push(RouteNames.studentAttendanceHistory),
                        ),
                      ),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space12)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.space20),
                          child: _AttendanceSummaryCard(
                              summary: provider.summary!),
                        ),
                      ),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space24)),
                    ],

                    // ── Quick Actions row ────────────────────────────────
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.space20),
                        child: _QuickActionsRow(
                          onAttendance: () =>
                              context.go(RouteNames.studentAttendance),
                          // Live-Test-16 ISSUE-2: push — see the 30-Day Summary
                          // header above; back must return to this dashboard.
                          onHistory: () =>
                              context.push(RouteNames.studentAttendanceHistory),
                          // FR-MODE-013: Meal Mode adds Today's Meals.
                          onMeals: provider.mealsEnabled
                              ? () => context.go(RouteNames.studentAttendance)
                              : null,
                          onMenu: provider.mealsEnabled &&
                                  provider.weeklyMenuEnabled
                              ? () => context.go(RouteNames.studentWeeklyMenu)
                              : null,
                          // command_3: billing summary + notepad one tap away.
                          // Live-Test-15 ISSUE-2: Meal Pricing is the master
                          // gate — with pricing OFF the group has no billing
                          // feature, so the card disappears exactly like the
                          // Menu card does when the weekly menu is off.
                          onBilling: provider.mealPricingEnabled
                              ? () => context.push(RouteNames.studentBilling)
                              : null,
                          onNotepad: () => context.push(RouteNames.notepad),
                        ),
                      ),
                    ),
                  ],

                  // ── Bottom padding ───────────────────────────────────────
                  const SliverToBoxAdapter(
                      child: SizedBox(height: AppConstants.space40)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Placeholder user (prevents null crash during first frame) ──────────────────
const _placeholderUser = UserModel(
  id: '',
  name: 'Student',
  email: '',
  role: UserRole.student,
  organizationId: '',
  groupIds: [],
  isVacationMode: false,
  isDefaultAttendance: false,
);

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space20),
      child: Row(
        children: [
          Text(
            title,
            style: AppTypography.titleSmall.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VacationBanner extends StatelessWidget {
  const _VacationBanner({this.onDisable, this.dateRange});
  final VoidCallback? onDisable;

  /// Approved vacation range, e.g. "22 Jun → 30 Jun". Null hides the line.
  final String? dateRange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space16,
        vertical: AppConstants.space12,
      ),
      decoration: BoxDecoration(
        color: AppColors.vacation.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: AppColors.vacation.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.beach_access_rounded,
              size: 20, color: AppColors.vacation),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Vacation Mode Active — attendance paused.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.vacation,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (dateRange != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Approved: $dateRange',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.vacation.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppConstants.space8),
          if (onDisable != null)
            GestureDetector(
              onTap: onDisable,
              child: Text(
                'Turn Off',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.vacation,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.vacation,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AttendanceSummaryCard extends StatelessWidget {
  const _AttendanceSummaryCard({required this.summary});
  final AttendanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppCard(
      padding: const EdgeInsets.all(AppConstants.space20),
      child: Column(
        children: [
          // ── Rate row ────────────────────────────────────────────────────
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${summary.attendancePercent.round()}%',
                    style: AppTypography.displaySmall.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Attendance rate',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              _RateRing(rate: summary.attendanceRate),
            ],
          ),

          const SizedBox(height: AppConstants.space16),

          // ── Progress bar ────────────────────────────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: summary.attendanceRate,
              backgroundColor:
                  isDark ? AppColors.borderDark : AppColors.surfaceVariant,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.present),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: AppConstants.space16),

          // ── Stats row ───────────────────────────────────────────────────
          Row(
            children: [
              _StatPill(
                  label: 'Present',
                  value: summary.presentCount,
                  color: AppColors.present),
              const SizedBox(width: AppConstants.space8),
              _StatPill(
                  label: 'Absent',
                  value: summary.absentCount,
                  color: AppColors.absent),
              const SizedBox(width: AppConstants.space8),
              _StatPill(
                  label: 'Pending',
                  value: summary.pendingCount,
                  color: AppColors.skipped),
              // Additive: excused vacation days, shown only when present so the
              // row stays clean for non-vacation students.
              if (summary.vacationDays > 0) ...[
                const SizedBox(width: AppConstants.space8),
                _StatPill(
                    label: 'Vacation',
                    value: summary.vacationDays,
                    color: AppColors.vacation),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RateRing extends StatelessWidget {
  const _RateRing({required this.rate});
  final double rate;

  @override
  Widget build(BuildContext context) {
    final color = rate >= 0.75
        ? AppColors.present
        : rate >= 0.5
            ? AppColors.skipped
            : AppColors.absent;

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: rate,
            strokeWidth: 5,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeCap: StrokeCap.round,
          ),
          Center(
            child: Text(
              '${(rate * 100).round()}',
              style: AppTypography.labelMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space8,
          vertical: AppConstants.space8,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.chipRadius),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: AppTypography.titleSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SRS FR-MODE-032 (LOOP-094) — explicit "No meal today" state for planner
/// off-days/holidays: nothing to mark, nothing billed, no wrong absences.
class _NoMealTodayCard extends StatelessWidget {
  const _NoMealTodayCard();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.space20),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppConstants.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No meal today',
                    style: AppTypography.titleSmall.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'No meal is scheduled for today — attendance is not required.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SRS FR-MODE-013 — mode-adaptive quick actions:
/// Attendance-Only shows {Attendance, History}; Meal Mode adds {Meals} and
/// {Menu} (the latter only when the Weekly Menu is enabled). command_3 adds
/// {Billing} and {Notepad}. Tiles flow onto extra rows of three so every
/// action keeps a comfortable tap target regardless of how many are enabled.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    this.onAttendance,
    this.onHistory,
    this.onMeals,
    this.onMenu,
    this.onBilling,
    this.onNotepad,
  });

  final VoidCallback? onAttendance;
  final VoidCallback? onHistory;
  final VoidCallback? onMeals;
  final VoidCallback? onMenu;
  final VoidCallback? onBilling;
  final VoidCallback? onNotepad;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _QuickActionTile(
        icon: Icons.how_to_reg_rounded,
        label: 'Attendance',
        color: AppColors.primary,
        onTap: onAttendance,
      ),
      _QuickActionTile(
        icon: Icons.history_rounded,
        label: 'History',
        color: AppColors.secondary,
        onTap: onHistory,
      ),
      if (onMeals != null)
        _QuickActionTile(
          icon: Icons.restaurant_rounded,
          label: 'Meals',
          color: AppColors.info,
          onTap: onMeals,
        ),
      if (onMenu != null)
        _QuickActionTile(
          icon: Icons.menu_book_rounded,
          label: 'Menu',
          color: AppColors.warning,
          onTap: onMenu,
        ),
      if (onBilling != null)
        _QuickActionTile(
          icon: Icons.receipt_long_rounded,
          label: 'Billing',
          color: AppColors.error,
          onTap: onBilling,
        ),
      if (onNotepad != null)
        _QuickActionTile(
          icon: Icons.edit_note_rounded,
          label: 'Notepad',
          color: AppColors.violet,
          onTap: onNotepad,
        ),
    ];

    // Chunk into rows of three; short rows are padded with spacers so tile
    // widths stay identical across rows.
    const perRow = 3;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += perRow) {
      final slice = tiles.sublist(
        i,
        i + perRow > tiles.length ? tiles.length : i + perRow,
      );
      final cells = <Widget>[];
      for (var j = 0; j < perRow; j++) {
        if (j > 0) cells.add(const SizedBox(width: AppConstants.space12));
        cells.add(
          Expanded(
            child: j < slice.length ? slice[j] : const SizedBox.shrink(),
          ),
        );
      }
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: AppConstants.space12));
      }
      rows.add(Row(children: cells));
    }
    return Column(children: rows);
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.space16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
            color: color.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: AppConstants.space6),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const AppDashboardSkeleton();
  }
}


class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 48,
              color: AppColors.error,
            ),
            const SizedBox(height: AppConstants.space16),
            Text(
              'Could not load dashboard',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.buttonRadius),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Group Switcher Row ──────────────────────────────────────────────────────

/// Horizontal chip row letting a multi-group student switch their active group.
/// ISSUE-001: labels show the REAL group name (from the user payload's
/// membership briefs); positional "Group N" remains only as a fallback for
/// payloads that predate the `groups` field. Raw group IDs are never shown.
/// MEM-013/015: premium group switcher. Displays joined groups as chips in the
/// member's saved (drag-reorderable) order and lets them switch the active
/// group. Long-press any chip to open the "Reorder groups" sheet.
class _GroupSwitcherRow extends StatefulWidget {
  const _GroupSwitcherRow({
    required this.groupIds,
    required this.groupBriefs,
    required this.activeGroupId,
    required this.onSwitch,
    required this.onJoinAnother,
    required this.isDark,
  });

  final List<String> groupIds;

  /// ISSUE-001: membership briefs ({id, name}) used to label the chips.
  final List<UserGroupBrief> groupBriefs;
  final String activeGroupId;
  final ValueChanged<String> onSwitch;
  // ISSUE 3: navigate to the join flow to add another group.
  final VoidCallback onJoinAnother;
  final bool isDark;

  @override
  State<_GroupSwitcherRow> createState() => _GroupSwitcherRowState();
}

class _GroupSwitcherRowState extends State<_GroupSwitcherRow> {
  List<String> _order = const [];
  String _userId = '';

  /// Real group name for [id]; positional fallback when unknown.
  String _nameFor(String id, int index) {
    for (final g in widget.groupBriefs) {
      if (g.id == id && g.name.trim().isNotEmpty) return g.name;
    }
    return 'Group ${index + 1}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_userId.isEmpty) {
      _userId = AuthProviderScope.of(context).currentUser?.id ?? '';
      GroupOrderService.instance.load(_userId).then((o) {
        if (mounted) setState(() => _order = o);
      });
    }
  }

  /// MEM-015: joined group ids in the member's saved order (new groups first).
  List<String> get _ordered =>
      GroupOrderService.instance.applyToIds(widget.groupIds, _order);

  Future<void> _saveOrder(List<String> ids) async {
    setState(() => _order = ids);
    await GroupOrderService.instance.save(_userId, ids);
  }

  /// MEM-015: drag-and-drop reorder sheet.
  Future<void> _openReorderSheet() async {
    final working = List<String>.from(_ordered);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: BoxDecoration(
            color: widget.isDark ? AppColors.surfaceDark : AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Reorder groups',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(ctx).colorScheme.onSurface)),
              const SizedBox(height: 4),
              Text('Drag to change the order of your group switcher.',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Flexible(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  itemCount: working.length,
                  onReorder: (oldI, newI) {
                    setLocal(() {
                      if (newI > oldI) newI -= 1;
                      final m = working.removeAt(oldI);
                      working.insert(newI, m);
                    });
                  },
                  itemBuilder: (c, i) {
                    final id = working[i];
                    final active = id == widget.activeGroupId;
                    return ListTile(
                      key: ValueKey(id),
                      leading: const Icon(Icons.drag_indicator_rounded),
                      title: Text(
                        '${_nameFor(id, i)}${active ? '  (active)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: active
                          ? const Icon(Icons.check_circle_rounded,
                              color: AppColors.primary, size: 18)
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await _saveOrder(working);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  child: const Text('Save order'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ordered;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // #9: align the group chips to the same 20px margin as the hero.
        padding:
            const EdgeInsets.symmetric(horizontal: AppConstants.space20),
        // +1 trailing "Join another" action chip (ISSUE 3).
        itemCount: ids.length + 1,
        separatorBuilder: (_, _) =>
            const SizedBox(width: AppConstants.space8),
        itemBuilder: (context, i) {
          if (i == ids.length) {
            return ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Join'),
              onPressed: widget.onJoinAnother,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.chipRadius),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.5),
                ),
              ),
            );
          }
          final id = ids[i];
          final selected = id == widget.activeGroupId;
          // MEM-015: long-press opens the drag-reorder sheet.
          return GestureDetector(
            onLongPress: _openReorderSheet,
            child: ChoiceChip(
              // ISSUE-001: real group name; constrained so very long names
              // stay a single tidy chip instead of stretching the row.
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  _nameFor(id, i),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              selected: selected,
              onSelected: (_) => widget.onSwitch(id),
              selectedColor: AppColors.primary.withValues(alpha: 0.15),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : null,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.chipRadius),
              ),
            ),
          );
        },
      ),
    );
  }
}

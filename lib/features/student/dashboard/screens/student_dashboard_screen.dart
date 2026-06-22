import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/notices/widgets/notice_bell.dart';
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
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/features/student/meals/screens/meal_detail_screen.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';
import 'package:smart_meal_management/shared/widgets/app_glass_card.dart';

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

  /// The group currently selected in the group-switcher chip row.
  /// Null means use the user's default [UserModel.groupId].
  String? _activeGroupId;

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

  /// Returns [user] with [groupId] overridden to [_activeGroupId] when set.
  UserModel _userWithActiveGroup(UserModel user) {
    if (_activeGroupId == null) return user;
    return user.copyWith(groupId: _activeGroupId);
  }

  /// Switches the active group and reloads dashboard data.
  Future<void> _switchGroup(String groupId) async {
    if (_activeGroupId == groupId) return;
    setState(() => _activeGroupId = groupId);
    final user = _authProvider?.currentUser;
    if (user != null) {
      final provider = StudentDashboardScope.of(context);
      await provider.load(user: _userWithActiveGroup(user));
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
    // Issue 1: honor per-day/meal-level preference (overlaid by the backend on
    // /meals/today), not just the group-level flag. If this meal requires a
    // preference, route to the attendance screen so the student picks a tag.
    final requiresPreference =
        (meal.preferencesEnabled || provider.preferencesEnabled) &&
            (meal.enabledPreferences.isNotEmpty ||
                provider.enabledPreferences.isNotEmpty);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.actionError ?? 'Could not mark attendance'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Issue #1: skips the current meal directly from the dashboard.
  Future<void> _skipFromDashboard(
    StudentDashboardProvider provider,
    MealModel meal,
  ) async {
    final user = _authProvider?.currentUser;
    if (user == null) return;
    final ok = await provider.markStatus(
      user: _userWithActiveGroup(user),
      meal: meal,
      status: AttendanceStatus.skipped,
    );
    if (!mounted) return;
    if (!ok) {
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
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
        ),
      );
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.space12),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: NoticeBell(
                          organizationId: currentUser.organizationId,
                          groupId: _activeGroupId ?? currentUser.groupId,
                          isAdmin: false,
                        ),
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
                        activeGroupId: _activeGroupId ??
                            currentUser.groupId ??
                            currentUser.effectiveGroupIds.first,
                        onSwitch: _switchGroup,
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
                          onDisable: () =>
                              context.go(RouteNames.studentSettings),
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
                    // ── Open Now carousel (Feature 3) ────────────────────
                    // Multi-card pager: auto-scrolls when all open meals are
                    // marked, otherwise parks on the first pending meal to force
                    // attention. Falls back to a single card when only one meal
                    // qualifies (same look as the original hero card).
                    if (provider.mealsEnabled &&
                        provider.openNowMeals.isNotEmpty)
                      SliverToBoxAdapter(
                        child: OpenNowCarousel(
                          meals: provider.openNowMeals,
                          pendingIndex: provider.firstPendingOpenIndex,
                          statusOf: (m) => provider.statusForMeal(m.id),
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

                    // ── 30-Day Attendance Summary ─────────────────────────
                    if (provider.summary != null) ...[
                      SliverToBoxAdapter(
                        child: _SectionHeader(
                          title: '30-Day Summary',
                          actionLabel: 'History',
                          onAction: () =>
                              context.go(RouteNames.studentAttendanceHistory),
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
                          onHistory: () =>
                              context.go(RouteNames.studentAttendanceHistory),
                          onMenu: provider.mealsEnabled &&
                                  provider.weeklyMenuEnabled
                              ? () => context.go(RouteNames.studentWeeklyMenu)
                              : null,
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

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    this.onAttendance,
    this.onHistory,
    this.onMenu,
  });

  final VoidCallback? onAttendance;
  final VoidCallback? onHistory;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionTile(
            icon: Icons.how_to_reg_rounded,
            label: 'Attendance',
            color: AppColors.primary,
            onTap: onAttendance,
          ),
        ),
        const SizedBox(width: AppConstants.space12),
        Expanded(
          child: _QuickActionTile(
            icon: Icons.history_rounded,
            label: 'History',
            color: AppColors.secondary,
            onTap: onHistory,
          ),
        ),
        if (onMenu != null) ...[
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: _QuickActionTile(
              icon: Icons.menu_book_rounded,
              label: 'Menu',
              color: AppColors.warning,
              onTap: onMenu,
            ),
          ),
        ],
      ],
    );
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 2.5,
          ),
          const SizedBox(height: AppConstants.space16),
          Text(
            'Loading dashboard…',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
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
/// Labels are positional ("Group N") — raw group IDs are never shown.
class _GroupSwitcherRow extends StatelessWidget {
  const _GroupSwitcherRow({
    required this.groupIds,
    required this.activeGroupId,
    required this.onSwitch,
    required this.isDark,
  });

  final List<String> groupIds;
  final String activeGroupId;
  final ValueChanged<String> onSwitch;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: AppConstants.space16),
        itemCount: groupIds.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: AppConstants.space8),
        itemBuilder: (context, i) {
          final id = groupIds[i];
          final selected = id == activeGroupId;
          return ChoiceChip(
            label: Text('Group ${i + 1}'),
            selected: selected,
            onSelected: (_) => onSwitch(id),
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : null,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.chipRadius),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/attendance/screens/my_corrections_screen.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/attendance_action_card.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/correction_request_sheet.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/guest_sheet.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/utils/verification_gate.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Student attendance screen — today's meals with per-meal action cards.
///
/// ## State
/// One provider is created locally and disposed with this [State]:
///  - [StudentAttendanceProvider] — handles marking; owns attendance records.
///
/// [StudentDashboardProvider] is read from [StudentDashboardScope] (owned by
/// [StudentShell]) — no duplicate API calls on tab switch (G1 fix).
///
/// Both are wired to [ListenableBuilder] — no manual `addListener/setState`.
///
/// ## Layout
/// ```
/// [AppBar — "Attendance" + History shortcut]
/// ── Vacation banner (conditional) ──────────
/// ── Default attendance chip (conditional) ──
/// ── Meal action cards (scrollable) ─────────
/// ```
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  // Dashboard data is shared via StudentDashboardScope (owned by StudentShell).
  // Only the attendance-specific provider is owned and disposed here — this
  // matches the TodayMealsScreen pattern (P3-6 fix) and prevents duplicate
  // API calls each time the Attendance tab is selected (G1 fix).
  // Issue 1: attendance status + marking flow through the SHARED
  // StudentDashboardProvider (shell-level), so a mark made here, on the Meals
  // tab, or on Home stays consistent everywhere — already-marked meals show the
  // submitted status instead of re-prompting "Mark Present".
  bool _ensuredLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ensuredLoad) return;
    _ensuredLoad = true;
    // Safety: ensure the shared dashboard is loaded if this tab opened first.
    final dash = StudentDashboardScope.maybeOf(context);
    final user = AuthProviderScope.of(context).currentUser;
    if (dash != null &&
        user != null &&
        dash.todayMeals.isEmpty &&
        !dash.isLoading) {
      dash.load(user: user);
    }
  }

  Future<void> _onRefresh() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    final dashProvider = StudentDashboardScope.maybeOf(context);
    if (dashProvider != null) await dashProvider.load(user: user);
  }

  /// Module 33 (ISSUE-17): raise a correction request for a closed meal.
  /// The record (and bill) only changes after admin approval — auto-approved
  /// decreases come back status=approved and refresh immediately.
  Future<void> _openCorrectionSheet(MealModel meal) async {
    final dashProvider = StudentDashboardScope.maybeOf(context);
    final created = await showCorrectionRequestSheet(
      context,
      meals: dashProvider?.todayMeals ?? [meal],
      initialMeal: meal,
    );
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(created.isApproved
            ? 'Applied — your record has been corrected.'
            : 'Request sent — awaiting admin review.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // Auto-approved corrections change today's records — refresh silently.
    if (created.isApproved) {
      final user = AuthProviderScope.of(context).currentUser;
      if (user != null) dashProvider?.load(user: user);
    }
  }

  /// Module 22 (Pass 9): hosted-guest sheet for a Present-marked meal.
  /// FR-HG-031/033/034 — add with per-guest preference + live cost preview,
  /// edit and cancel; FR-HG-062 — confirm/decline admin-proposed guests.
  Future<void> _openGuestSheet(MealModel meal) async {
    final dashProvider = StudentDashboardScope.maybeOf(context);
    final user = AuthProviderScope.of(context).currentUser;
    final config = dashProvider?.groupConfig ?? const GroupMealConfig();
    final now = DateTime.now();
    final dateStr = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final record = dashProvider?.recordForMeal(meal.id);
    final enabledPrefs = meal.enabledPreferences.isNotEmpty
        ? meal.enabledPreferences
        : config.enabledPreferences.map((e) => e.name).toList();
    final changed = await showGuestSheet(
      context,
      mealId: meal.id,
      mealName: meal.name,
      dateStr: dateStr,
      config: config.guestConfig,
      pricingEnabled: config.mealPricingEnabled,
      enabledPreferences: enabledPrefs,
      // Live-Test-6 ISSUE-2: each guest picks the meal's preference groups.
      preferenceGroups: meal.preferenceGroups,
      mealPrice: record?.price ?? meal.price,
      currentUserId: user?.id,
    );
    // Guests changed the host's counters/billing — refresh silently.
    if (changed == true && mounted && user != null) {
      dashProvider?.load(user: user);
    }
  }

  Future<void> _mark(
    MealModel meal,
    AttendanceStatus status, {
    String? preference,
    List<PreferenceSelection>? selections,
  }) async {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) return;
    final dashProvider = StudentDashboardScope.maybeOf(context);
    if (dashProvider == null) return;
    final ok = await dashProvider.markStatus(
      user: user,
      meal: meal,
      status: status,
      preference: preference,
      selections: selections,
    );
    // SRS Module 03 ACC-005: unverified members get the guided verify flow.
    if (!ok && mounted) {
      await VerificationGate.handleMessage(
        context,
        dashProvider.actionError,
        email: user.email,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Read from the shell-level shared provider — do NOT create or dispose.
    final dashProvider = StudentDashboardScope.maybeOf(context);
    if (dashProvider == null) {
      return const Scaffold(
        body: AppListSkeleton(rows: 3, rowHeight: 150, headerHeight: 64),
      );
    }

    // Single shared provider drives all rebuilds (status + meals + marking).
    return ListenableBuilder(
      listenable: dashProvider,
      builder: (context, _) {
        final isLoading = dashProvider.isLoading;
        final meals = dashProvider.todayMeals;
        final isVacation = dashProvider.isVacationMode;

        // Guard — student has not joined any group yet.
        final currentUser = AuthProviderScope.of(context).currentUser;
        final hasGroup = currentUser?.effectiveGroupIds.isNotEmpty ?? false;

        return Scaffold(
          backgroundColor: isDark
              ? AppColors.backgroundDark
              : AppColors.background,
          // ── App Bar ──────────────────────────────────────────────────────
          appBar: _AttendanceAppBar(
            isDark: isDark,
            onHistoryTap: () => context.push(RouteNames.studentAttendanceHistory),
            onCorrectionsTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    MyCorrectionsScreen(meals: dashProvider.todayMeals),
              ),
            ),
          ),

          body: !hasGroup
              ? _NoGroupView(isDark: isDark)
              : isLoading
              ? const _LoadingView()
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _onRefresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space16)),

                      // ── Vacation mode banner ─────────────────────────────
                      if (isVacation)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.space16),
                            child: _VacationBanner(
                              // Live-Test-16 ISSUE-2: push, not go — Settings
                              // is a leaf; `go` left it with no back arrow and
                              // Android back closed the app.
                              onSettings: () =>
                                  context.push(RouteNames.studentSettings),
                            ),
                          ),
                        ),

                      if (isVacation)
                        const SliverToBoxAdapter(
                            child: SizedBox(height: AppConstants.space12)),

                      // ── Default attendance chip ──────────────────────────
                      if ((AuthProviderScope.of(context).currentUser?.isDefaultAttendance ?? false) && !isVacation)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.space16),
                            child: _DefaultAttendanceBanner(isDark: isDark),
                          ),
                        ),

                      if ((AuthProviderScope.of(context).currentUser?.isDefaultAttendance ?? false) && !isVacation)
                        const SliverToBoxAdapter(
                            child: SizedBox(height: AppConstants.space12)),

                      // ── No meals / empty state ───────────────────────────
                      // SRS FR-MODE-032 (LOOP-094): in planner mode an empty
                      // day is a holiday/off-day ("No meal today"), not a
                      // configuration problem.
                      if (meals.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoMealsView(
                            isDark: isDark,
                            isPlannerOffDay: (GroupConfigScope.maybeOf(context)
                                        ?.weeklyMenuEnabled ??
                                    false) ||
                                (GroupConfigScope.maybeOf(context)
                                        ?.dayWiseMealsEnabled ??
                                    false),
                          ),
                        )
                      else ...[
                        // ── Date/label header ──────────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppConstants.space16),
                            child: _DateHeader(isDark: isDark),
                          ),
                        ),
                        const SliverToBoxAdapter(
                            child: SizedBox(height: AppConstants.space12)),

                        // ── Meal action cards ──────────────────────────────
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.space16),
                          sliver: SliverList.separated(
                            itemCount: meals.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppConstants.space12),
                            itemBuilder: (context, i) {
                              final meal = meals[i];
                              final user = AuthProviderScope.of(context).currentUser;
                              final isDefaultAttend = user?.isDefaultAttendance ?? false;
                              // Read group config from shell scope (set by dashboard load).
                              final groupConfig = GroupConfigScope.maybeOf(context);
                              final groupEnabledPrefs =
                                  groupConfig?.enabledPreferences
                                      ?? dashProvider.enabledPreferences;
                              // Live-Test-9 ISSUE-003: the meal card from
                              // /meals/today IS the published day-effective
                              // truth — the server has already overlaid the
                              // published schedule (including a per-day
                              // "preferences OFF"). The old `|| group-level`
                              // fallback re-enabled the group's default tag
                              // set (Veg/Non-Veg/Egg/Fish/Chicken) on days the
                              // published schedule disabled preferences,
                              // blocking Present until a phantom pick. The
                              // group-level config now only fills in the TAG
                              // LIST for legacy meals that are enabled but
                              // carry no tags of their own.
                              final prefsEnabled = meal.preferencesEnabled;
                              final enabledPrefs = !prefsEnabled
                                  ? const <String>[]
                                  : meal.enabledPreferences.isNotEmpty
                                      ? meal.enabledPreferences
                                      : groupEnabledPrefs
                                          .map((e) => e.name)
                                          .toList();
                              final record =
                                  dashProvider.recordForMeal(meal.id);
                              return AttendanceActionCard(
                                meal: meal,
                                status: dashProvider.statusForMeal(meal.id),
                                markedPreference: record?.preference,
                                // Live-Test-9 ISSUE-4.1: the full per-group
                                // selection snapshot — rendered group-wise
                                // (never merged into one flat tag list).
                                markedSelections: record?.preferences,
                                markedAt: record?.markedAt,
                                isWindowOpen: dashProvider.isWindowOpen(meal),
                                isWindowClosed:
                                    dashProvider.isWindowPast(meal),
                                // FR-VACX-003: per-MEAL coverage — on a
                                // slot-bounded boundary day only meals inside
                                // the vacation range lock; earlier meals stay
                                // markable ("leaving after Evening Tea").
                                isVacationMode:
                                    dashProvider.isMealOnVacation(meal),
                                // SRS Module 03 ATT-011: Personal
                                // Auto-Attendance is SUSPENDED on
                                // preference-required meals — those stay
                                // manual (and auto-resume on the next
                                // no-preference meal, ATT-012).
                                isDefaultAttendance: isDefaultAttend &&
                                    !prefsEnabled &&
                                    meal.preferenceGroups.isEmpty,
                                preferencesEnabled: prefsEnabled,
                                enabledPreferences: enabledPrefs,
                                onMark: (s, {String? preference}) =>
                                    _mark(meal, s, preference: preference),
                                // Module 36: explicit-group meals send the
                                // full selection set (FR-PG-030/031).
                                onMarkWithSelections: (s, selections) =>
                                    _mark(meal, s, selections: selections),
                                // Module 33 (ISSUE-17): post-window correction
                                // request — hidden while THIS meal is covered
                                // by vacation (per-meal, FR-VACX-003).
                                onRequestCorrection:
                                    dashProvider.isMealOnVacation(meal)
                                        ? null
                                        : () => _openCorrectionSheet(meal),
                                // Module 22 (Pass 9): hosted guests — only in
                                // guest-enabled Meal Mode groups, never on a
                                // vacation-covered meal (FR-HG-043/VACX-008).
                                onManageGuests: (dashProvider
                                            .groupConfig.guestsEnabled &&
                                        !dashProvider.isMealOnVacation(meal))
                                    ? () => _openGuestSheet(meal)
                                    : null,
                              );
                            },
                          ),
                        ),

                        // ── Window expiry notice ───────────────────────────
                        if (meals.isNotEmpty &&
                            meals.every((m) => dashProvider.isWindowPast(m)))
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(AppConstants.space16),
                              child: _WindowClosedNotice(isDark: isDark),
                            ),
                          ),
                      ],

                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space40)),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

// ── App Bar ────────────────────────────────────────────────────────────────────

class _AttendanceAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _AttendanceAppBar({
    required this.isDark,
    required this.onHistoryTap,
    required this.onCorrectionsTap,
  });

  final bool isDark;
  final VoidCallback onHistoryTap;

  /// Module 33 (ISSUE-17): opens "My Corrections" — post-window requests,
  /// admin confirmations, and their statuses.
  final VoidCallback onCorrectionsTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(
        'Attendance',
        style: AppTypography.titleLarge.copyWith(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'My corrections',
          onPressed: onCorrectionsTap,
          icon: const Icon(
            Icons.rule_rounded,
            size: 20,
            color: AppColors.primary,
          ),
        ),
        TextButton.icon(
          onPressed: onHistoryTap,
          icon: const Icon(
            Icons.history_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          label: Text(
            'History',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.space8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

// ── Date header ────────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekday = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ][now.weekday - 1];
    final month = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][now.month - 1];

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Today's Meals",
              style: AppTypography.titleSmall.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$weekday, $month ${now.day}',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Vacation banner ────────────────────────────────────────────────────────────

class _VacationBanner extends StatelessWidget {
  const _VacationBanner({this.onSettings});
  final VoidCallback? onSettings;

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
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.beach_access_rounded,
              size: 18, color: AppColors.vacation),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Text(
              'Vacation Mode is ON — attendance is paused.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.vacation,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onSettings != null)
            GestureDetector(
              onTap: onSettings,
              child: Text(
                'Settings',
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

// ── Default attendance banner ──────────────────────────────────────────────────

class _DefaultAttendanceBanner extends StatelessWidget {
  const _DefaultAttendanceBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Default Attendance ON — you are auto-marked present.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── No group joined state ──────────────────────────────────────────────────────

class _NoGroupView extends StatelessWidget {
  const _NoGroupView({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.group_off_rounded,
                size: 34,
                color: AppColors.warning,
              ),
            ),
            const SizedBox(height: AppConstants.space20),
            Text(
              'Not in a group yet',
              style: AppTypography.titleMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Ask your group admin for the QR code and scan it to join your group.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space24),
            FilledButton.icon(
              onPressed: () => context.push(RouteNames.groupJoin),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('Scan QR Code'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── No meals empty state ───────────────────────────────────────────────────────

class _NoMealsView extends StatelessWidget {
  const _NoMealsView({required this.isDark, this.isPlannerOffDay = false});
  final bool isDark;

  /// SRS FR-MODE-032: planner mode + empty day = holiday/off-day, shown as an
  /// explicit "No meal today" state (unmarkable, unbilled) — not a config error.
  final bool isPlannerOffDay;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                isPlannerOffDay
                    ? Icons.event_busy_rounded
                    : Icons.no_meals_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppConstants.space20),
            Text(
              isPlannerOffDay ? 'No meal today' : 'No meal configured',
              style: AppTypography.titleMedium.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              isPlannerOffDay
                  ? 'No meal is scheduled for today.\n'
                      'Attendance is not required — nothing will be billed.'
                  : 'No meal has been configured by the admin/manager.\n'
                      'Attendance is not allowed.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── All windows closed notice ──────────────────────────────────────────────────

class _WindowClosedNotice extends StatelessWidget {
  const _WindowClosedNotice({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space16,
        vertical: AppConstants.space12,
      ),
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: AppColors.textTertiary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock_clock_rounded,
            size: 16,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'All attendance windows are closed for today. Your Admin can still update attendance manually.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading view ───────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const AppListSkeleton(rows: 3, rowHeight: 150, headerHeight: 64);
  }
}
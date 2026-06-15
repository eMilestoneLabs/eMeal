import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/attendance/providers/student_attendance_provider.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/attendance_action_card.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

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
  late final StudentAttendanceProvider _attendanceProvider;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _attendanceProvider = StudentAttendanceProvider();

      final auth = AuthProviderScope.of(context);
      if (auth.currentUser != null) {
        final user = auth.currentUser!;
        final groupId = user.effectiveGroupIds.firstOrNull;
        // Only load when the student has actually joined a group.
        if (groupId != null) {
          _attendanceProvider.load(
            userId: user.id,
            groupId: groupId,
            organizationId: user.organizationId,
          );
          // StudentDashboardProvider is shared — StudentShell already loaded it.
          // No separate load needed here; reading from scope below.
        }
      }
    }
  }

  @override
  void dispose() {
    _attendanceProvider.dispose();
    // Do NOT dispose the StudentDashboardScope provider — it is owned by StudentShell.
    super.dispose();
  }

  Future<void> _onRefresh() async {
    final auth = AuthProviderScope.of(context);
    if (auth.currentUser == null) return;
    final user = auth.currentUser!;
    final groupId = user.effectiveGroupIds.firstOrNull;
    if (groupId == null) return;
    final dashProvider = StudentDashboardScope.maybeOf(context);
    await Future.wait([
      _attendanceProvider.load(
        userId: user.id,
        groupId: groupId,
        organizationId: user.organizationId,
      ),
      if (dashProvider != null) dashProvider.load(user: user),
    ]);
  }

  void _mark(String mealId, AttendanceStatus status, {String? preference}) {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    final groupId = user?.effectiveGroupIds.firstOrNull;
    if (user == null || groupId == null) return;
    _attendanceProvider.markAttendance(
      mealId: mealId,
      userId: user.id,
      groupId: groupId,
      organizationId: user.organizationId,
      status: status,
      preference: preference,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Read from the shell-level shared provider — do NOT create or dispose.
    final dashProvider = StudentDashboardScope.maybeOf(context);
    if (dashProvider == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5),
        ),
      );
    }

    // Merge both providers so a single ListenableBuilder handles all rebuilds.
    return ListenableBuilder(
      listenable: Listenable.merge([_attendanceProvider, dashProvider]),
      builder: (context, _) {
        final isLoading = _attendanceProvider.isLoading || dashProvider.isLoading;
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
                              onSettings: () =>
                                  context.go(RouteNames.studentSettings),
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
                      if (meals.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoMealsView(isDark: isDark),
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
                              final prefsEnabled = groupConfig?.preferencesEnabled
                                  ?? dashProvider.preferencesEnabled;
                              final enabledPrefs = groupConfig?.enabledPreferences
                                  ?? dashProvider.enabledPreferences;
                              return AttendanceActionCard(
                                meal: meal,
                                status: _attendanceProvider.statusForMeal(meal.id),
                                isWindowOpen: dashProvider.isWindowOpen(meal),
                                isVacationMode: isVacation,
                                isDefaultAttendance: isDefaultAttend,
                                preferencesEnabled: prefsEnabled,
                                enabledPreferences: enabledPrefs,
                                onMark: (s, {String? preference}) =>
                                    _mark(meal.id, s, preference: preference),
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
  });

  final bool isDark;
  final VoidCallback onHistoryTap;

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
  const _NoMealsView({required this.isDark});
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
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.no_meals_rounded,
                size: 34,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppConstants.space20),
            Text(
              'Attendance not open yet',
              style: AppTypography.titleMedium.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              "Your group hasn't set up an attendance slot yet.\n"
              'Once your admin adds one, you can mark attendance here.',
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
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.primary,
        strokeWidth: 2.5,
      ),
    );
  }
}


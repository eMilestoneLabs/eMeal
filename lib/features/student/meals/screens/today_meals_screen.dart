import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

/// Student "Meals" tab screen — today's meal cards with attendance marking.
///
/// Combines meal content (name, timing, menu items) with 1-tap attendance
/// so students don't need to switch to the Attendance tab for quick marking.
///
/// State is driven by two providers, merged into a single [ListenableBuilder]:
/// - [StudentDashboardProvider] — today's meals, window timings, vacation mode
/// - [StudentAttendanceProvider] — optimistic attendance records + mark action
class TodayMealsScreen extends StatefulWidget {
  const TodayMealsScreen({super.key});

  @override
  State<TodayMealsScreen> createState() => _TodayMealsScreenState();
}

class _TodayMealsScreenState extends State<TodayMealsScreen> {
  // Issue 1: attendance status + marking now flow through the SHARED
  // StudentDashboardProvider (shell-level) instead of a local provider. This
  // keeps the Meals tab, Attendance tab and Home in sync — a mark made on any
  // surface is immediately reflected on the others (no stale "Mark Present").
  bool _ensuredLoad = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ensuredLoad) return;
    _ensuredLoad = true;
    // Safety: if the app opened directly on this tab before Home loaded the
    // shared dashboard, kick off the load once (no-op if already loaded).
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
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) return;
    final dashboardProvider = StudentDashboardScope.maybeOf(context);
    if (dashboardProvider != null) await dashboardProvider.load(user: user);
  }

  void _mark(MealModel meal, AttendanceStatus status, {String? preference}) {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) return;
    final dashboardProvider = StudentDashboardScope.maybeOf(context);
    if (dashboardProvider == null) return;
    dashboardProvider.markStatus(
      user: user,
      meal: meal,
      status: status,
      preference: preference,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Read from the shell-level shared provider — no duplicate API calls.
    final dashboardProvider = StudentDashboardScope.maybeOf(context);
    if (dashboardProvider == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5)),
      );
    }

    return ListenableBuilder(
      listenable: dashboardProvider,
      builder: (context, _) {
        final isLoading = dashboardProvider.isLoading;
        final meals = dashboardProvider.todayMeals;
        final isVacation = dashboardProvider.isVacationMode;
        final isDefaultAttend =
            AuthProviderScope.of(context).currentUser?.isDefaultAttendance ??
                false;

        return Scaffold(
          backgroundColor:
              isDark ? AppColors.backgroundDark : AppColors.background,
          appBar: _MealsAppBar(isDark: isDark),
          body: isLoading
              ? const _LoadingView()
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _onRefresh,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppConstants.space16),
                      ),

                      // ── Vacation banner ───────────────────────────────────
                      if (isVacation)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.space16,
                            ),
                            child: _VacationBanner(
                              onSettings: () =>
                                  context.push(RouteNames.studentSettings),
                            ),
                          ),
                        ),
                      if (isVacation)
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space12),
                        ),

                      // ── Default attendance notice ─────────────────────────
                      if (isDefaultAttend && !isVacation)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.space16,
                            ),
                            child: _DefaultAttendanceBanner(isDark: isDark),
                          ),
                        ),
                      if (isDefaultAttend && !isVacation)
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space12),
                        ),

                      // ── Empty state ────────────────────────────────────────
                      if (meals.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _NoMealsView(isDark: isDark),
                        )
                      else ...[
                        // ── Date header ────────────────────────────────────
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppConstants.space16,
                            ),
                            child: _DateHeader(isDark: isDark),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: AppConstants.space12),
                        ),

                        // ── Meal cards ─────────────────────────────────────
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.space16,
                          ),
                          sliver: SliverList.separated(
                            itemCount: meals.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: AppConstants.space16),
                            itemBuilder: (context, i) {
                              final meal = meals[i];
                              final status =
                                  dashboardProvider.statusForMeal(meal.id);
                              final isOpen =
                                  dashboardProvider.isWindowOpen(meal);
                              final isPast =
                                  dashboardProvider.isWindowPast(meal);
                              return _TodayMealCard(
                                meal: meal,
                                status: status,
                                // Issue 5: once marked, show the price that was
                                // snapshotted at mark time (matches billing),
                                // not the live meal price which may have changed.
                                snapshotPrice: dashboardProvider
                                    .snapshotPriceForMeal(meal.id),
                                isWindowOpen: isOpen,
                                isWindowPast: isPast,
                                isVacationMode: isVacation,
                                isDefaultAttend: isDefaultAttend,
                                preferencesEnabled: meal.preferencesEnabled ||
                                    dashboardProvider.preferencesEnabled,
                                enabledPreferences:
                                    meal.enabledPreferences.isNotEmpty
                                        ? meal.enabledPreferences
                                        : dashboardProvider.enabledPreferences
                                            .map((e) => e.name)
                                            .toList(),
                                onMark: (s, pref) =>
                                    _mark(meal, s, preference: pref),
                              );
                            },
                          ),
                        ),

                        // ── Window closed notice ──────────────────────────
                        if (meals.isNotEmpty &&
                            meals.every(
                              (m) => dashboardProvider.isWindowPast(m),
                            ))
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(
                                AppConstants.space16,
                              ),
                              child: _WindowClosedNotice(isDark: isDark),
                            ),
                          ),
                      ],

                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppConstants.space40),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

// ── App bar ────────────────────────────────────────────────────────────────────

class _MealsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _MealsAppBar({required this.isDark});
  final bool isDark;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr = '${months[now.month - 1]} ${now.day}';

    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Today\'s Meals',
            style: AppTypography.titleLarge.copyWith(
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            dateStr,
            style: AppTypography.labelSmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
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
    final weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];

    return Text(
      '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}',
      style: AppTypography.titleSmall.copyWith(
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ── Today meal card ────────────────────────────────────────────────────────────

/// Rich card combining meal info + 1-tap attendance marking.
class _TodayMealCard extends StatefulWidget {
  const _TodayMealCard({
    required this.meal,
    required this.status,
    required this.isWindowOpen,
    required this.isWindowPast,
    required this.isVacationMode,
    required this.isDefaultAttend,
    required this.onMark,
    this.snapshotPrice,
    this.preferencesEnabled = false,
    this.enabledPreferences = const [],
  });

  final MealModel meal;
  final AttendanceStatus? status;

  /// Issue 5: price snapshotted on the attendance record (shown once marked).
  final int? snapshotPrice;

  final bool isWindowOpen;
  final bool isWindowPast;
  final bool isVacationMode;
  final bool isDefaultAttend;
  final bool preferencesEnabled;
  final List<String> enabledPreferences;
  final void Function(AttendanceStatus status, String? preference) onMark;

  @override
  State<_TodayMealCard> createState() => _TodayMealCardState();
}

class _TodayMealCardState extends State<_TodayMealCard> {
  String? _selectedPref;

  bool get _canMark =>
      widget.isWindowOpen &&
      !widget.isVacationMode &&
      (widget.status == null || widget.status == AttendanceStatus.pending);

  bool get _isMarked =>
      widget.status != null && widget.status != AttendanceStatus.pending;

  /// Issue 5: once the meal is marked, show the snapshot price that was billed;
  /// otherwise show the live meal price. Null hides the price chip.
  int? get _displayPrice =>
      (_isMarked && widget.snapshotPrice != null)
          ? widget.snapshotPrice
          : widget.meal.price;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = MealModel.iconBgColor(widget.meal.order);
    final fgColor = MealModel.iconFgColor(widget.meal.order);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: _borderColor(isDark),
          width: _isMarked ? 1.5 : 1.0,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: _shadowColor(),
                  blurRadius: _isMarked ? 12 : 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Meal header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(AppConstants.space16),
            child: Row(
              children: [
                // Icon container
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.meal.icon, color: fgColor, size: 24),
                ),
                const SizedBox(width: AppConstants.space12),

                // Meal name + timing
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.meal.name,
                        style: AppTypography.titleSmall.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${widget.meal.attendanceWindow.openTime}'
                            ' – ${widget.meal.attendanceWindow.closeTime}',
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                          // Show meal price. Issue 5: once marked, prefer the
                          // snapshot price (what was billed) over the live price.
                          if (_displayPrice != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '• ₹$_displayPrice',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Status badge
                _StatusBadge(
                  status: widget.status,
                  isWindowOpen: widget.isWindowOpen,
                  isVacationMode: widget.isVacationMode,
                ),
              ],
            ),
          ),

          // ── Meal image gallery ─────────────────────────────────────────
          if (widget.meal.imageBytes.isNotEmpty)
            _MealImageGallery(
              imageBytes: widget.meal.imageBytes,
              isDark: isDark,
            ),

          // ── Menu items preview ─────────────────────────────────────────
          if (widget.meal.menuItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space16,
                0,
                AppConstants.space16,
                AppConstants.space12,
              ),
              child: Wrap(
                spacing: AppConstants.space6,
                runSpacing: 6,
                // Issue 4: show ALL configured menu items (no 4-item cap) so the
                // student sees every item the admin added for this meal/day.
                children: widget.meal.menuItems
                    .map(
                      (item) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.space8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.surfaceVariantDark
                              : AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(
                            AppConstants.chipRadius,
                          ),
                        ),
                        child: Text(
                          item,
                          style: AppTypography.labelSmall.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

          // ── Divider ────────────────────────────────────────────────────
          if (!_isMarked || widget.isVacationMode)
            Divider(
              height: 1,
              color: isDark
                  ? AppColors.borderDark.withValues(alpha: 0.4)
                  : AppColors.border,
            ),

          // ── Vacation state ─────────────────────────────────────────────
          if (widget.isVacationMode)
            Padding(
              padding: const EdgeInsets.all(AppConstants.space12),
              child: Row(
                children: [
                  const Icon(
                    Icons.beach_access_rounded,
                    size: 14,
                    color: AppColors.vacation,
                  ),
                  const SizedBox(width: AppConstants.space8),
                  Text(
                    'Attendance paused — vacation mode is ON',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.vacation,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )

          // ── Already marked state ───────────────────────────────────────
          else if (_isMarked)
            _MarkedState(
              status: widget.status!,
              isDark: isDark,
              canChange: widget.isWindowOpen,
              windowClosed: widget.isWindowPast,
              onMark: (s) => widget.onMark(s, _selectedPref),
            )

          // ── Action area (pending + window open/past) ───────────────────
          else ...[
            // Default attendance flip: show "Mark Absent" as primary when on
            if (widget.isDefaultAttend && widget.isWindowOpen)
              _DefaultAttendActions(
                onMarkAbsent: () =>
                    widget.onMark(AttendanceStatus.absent, _selectedPref),
                onMarkSkipped: () =>
                    widget.onMark(AttendanceStatus.skipped, _selectedPref),
                isDark: isDark,
              )
            else if (widget.isWindowOpen)
              _AttendActions(
                canMark: _canMark,
                preference: _selectedPref,
                onPreferenceChanged: (p) => setState(() => _selectedPref = p),
                onMark: (s) => widget.onMark(s, _selectedPref),
                preferencesEnabled: widget.preferencesEnabled,
                enabledPreferences: widget.enabledPreferences,
              )
            else if (widget.isWindowPast)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.space16,
                  AppConstants.space12,
                  AppConstants.space16,
                  AppConstants.space12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_clock_rounded,
                      size: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppConstants.space8),
                    Text(
                      'Attendance window closed',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.space16,
                  AppConstants.space12,
                  AppConstants.space16,
                  AppConstants.space12,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      size: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textTertiary,
                    ),
                    const SizedBox(width: AppConstants.space8),
                    Text(
                      'Attendance not open yet',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Color _borderColor(bool isDark) {
    if (widget.isVacationMode) {
      return AppColors.vacation.withValues(alpha: 0.2);
    }
    switch (widget.status) {
      case AttendanceStatus.present:
        return AppColors.present.withValues(alpha: 0.3);
      case AttendanceStatus.absent:
        return AppColors.absent.withValues(alpha: 0.3);
      case AttendanceStatus.skipped:
        return AppColors.skipped.withValues(alpha: 0.3);
      default:
        return isDark
            ? AppColors.borderDark.withValues(alpha: 0.5)
            : AppColors.border;
    }
  }

  Color _shadowColor() {
    switch (widget.status) {
      case AttendanceStatus.present:
        return AppColors.present.withValues(alpha: 0.08);
      case AttendanceStatus.absent:
        return AppColors.absent.withValues(alpha: 0.06);
      case AttendanceStatus.skipped:
        return AppColors.skipped.withValues(alpha: 0.06);
      default:
        return AppColors.primary.withValues(alpha: 0.04);
    }
  }
}

// ── Attendance action rows ─────────────────────────────────────────────────────

/// Standard 3-button row: Present / Skip / Absent
///
/// When [preferencesEnabled] is true and [enabledPreferences] is non-empty,
/// a premium chip selector is shown above the buttons. The student must pick
/// a preference before the Present button becomes fully active.
class _AttendActions extends StatelessWidget {
  const _AttendActions({
    required this.canMark,
    required this.preference,
    required this.onPreferenceChanged,
    required this.onMark,
    this.preferencesEnabled = false,
    this.enabledPreferences = const [],
  });

  final bool canMark;
  final String? preference;
  final ValueChanged<String?> onPreferenceChanged;
  final void Function(AttendanceStatus) onMark;
  final bool preferencesEnabled;
  final List<String> enabledPreferences;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showPrefs =
        preferencesEnabled && enabledPreferences.isNotEmpty;
    // Spec gating: Present stays disabled until a preference is picked when
    // preferences are required; Skip / Absent remain enabled regardless.
    final canMarkPresent = canMark && (!showPrefs || preference != null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space16,
        AppConstants.space12,
        AppConstants.space16,
        AppConstants.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Meal preference chips ──────────────────────────────────────
          if (showPrefs) ...[
            Row(
              children: [
                const Icon(Icons.tune_rounded,
                    size: 13, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  'Select preference',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.space8),
            Wrap(
              spacing: AppConstants.space8,
              runSpacing: AppConstants.space6,
              children: enabledPreferences.map((pref) {
                final isSelected = preference == pref;
                final disp = MealPreferenceOption.display(pref);
                return GestureDetector(
                  onTap: canMark
                      ? () => onPreferenceChanged(
                          isSelected ? null : pref)
                      : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : isDark
                              ? AppColors.surfaceVariantDark
                              : AppColors.surfaceVariant,
                      borderRadius:
                          BorderRadius.circular(AppConstants.chipRadius),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : isDark
                                ? AppColors.borderDark
                                : AppColors.border,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          disp.emoji,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          disp.label,
                          style: AppTypography.labelSmall.copyWith(
                            color: isSelected
                                ? Colors.white
                                : isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppConstants.space12),
          ],

          // ── Action buttons ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed:
                      canMarkPresent ? () => onMark(AttendanceStatus.present) : null,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Present'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.present,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.space8),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed:
                      canMark ? () => onMark(AttendanceStatus.skipped) : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: AppConstants.space8),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed:
                      canMark ? () => onMark(AttendanceStatus.absent) : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.absent,
                    side: BorderSide(
                      color: canMark
                          ? AppColors.absent.withValues(alpha: 0.5)
                          : AppColors.textTertiary.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Absent'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Default attendance flip: "Mark Absent" is primary; "Skip" is secondary.
class _DefaultAttendActions extends StatelessWidget {
  const _DefaultAttendActions({
    required this.onMarkAbsent,
    required this.onMarkSkipped,
    required this.isDark,
  });

  final VoidCallback onMarkAbsent;
  final VoidCallback onMarkSkipped;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space16,
        AppConstants.space12,
        AppConstants.space16,
        AppConstants.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Auto-marked Present — tap only if changing:',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppConstants.space8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onMarkAbsent,
                  icon: const Icon(
                    Icons.cancel_outlined,
                    size: 16,
                    color: AppColors.absent,
                  ),
                  label: const Text('Mark Absent'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.absent,
                    side: BorderSide(
                      color: AppColors.absent.withValues(alpha: 0.4),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.space8),
              Expanded(
                child: OutlinedButton(
                  onPressed: onMarkSkipped,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    textStyle: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Skip'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows confirmed status with optional undo (re-mark) when window is still open.
class _MarkedState extends StatelessWidget {
  const _MarkedState({
    required this.status,
    required this.isDark,
    required this.canChange,
    required this.onMark,
    this.windowClosed = false,
  });

  final AttendanceStatus status;
  final bool isDark;
  final bool canChange;
  final bool windowClosed;
  final void Function(AttendanceStatus) onMark;

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _props(status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space16,
        AppConstants.space12,
        AppConstants.space16,
        AppConstants.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AppConstants.space8),
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (canChange) ...[
                const Spacer(),
                TextButton(
                  onPressed: () => _showChangeSheet(context),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.space8,
                      vertical: 4,
                    ),
                  ),
                  child: Text(
                    'Change',
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // Window has closed — make it explicit that the meal can't change.
          if (windowClosed) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.lock_clock_rounded,
                    size: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Attendance closed — you can no longer change this meal.',
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (IconData, String, Color) _props(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return (Icons.check_circle_rounded, 'Marked Present', AppColors.present);
      case AttendanceStatus.absent:
        return (Icons.cancel_rounded, 'Marked Absent', AppColors.absent);
      case AttendanceStatus.skipped:
        return (Icons.remove_circle_rounded, 'Skipped', AppColors.skipped);
      case AttendanceStatus.onVacation:
        return (
          Icons.beach_access_rounded,
          'On Vacation',
          AppColors.vacation,
        );
      case AttendanceStatus.pending:
        return (Icons.pending_rounded, 'Pending', AppColors.warning);
    }
  }

  void _showChangeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangeStatusSheet(onMark: onMark),
    );
  }
}

class _ChangeStatusSheet extends StatelessWidget {
  const _ChangeStatusSheet({required this.onMark});
  final void Function(AttendanceStatus) onMark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppConstants.space24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.bottomSheetRadius),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change attendance',
            style: AppTypography.titleMedium.copyWith(
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.space16),
          _SheetOption(
            icon: Icons.check_circle_rounded,
            label: 'Mark Present',
            color: AppColors.present,
            onTap: () {
              Navigator.of(context).pop();
              onMark(AttendanceStatus.present);
            },
          ),
          const SizedBox(height: AppConstants.space8),
          _SheetOption(
            icon: Icons.remove_circle_rounded,
            label: 'Skip',
            color: AppColors.skipped,
            onTap: () {
              Navigator.of(context).pop();
              onMark(AttendanceStatus.skipped);
            },
          ),
          const SizedBox(height: AppConstants.space8),
          _SheetOption(
            icon: Icons.cancel_rounded,
            label: 'Mark Absent',
            color: AppColors.absent,
            onTap: () {
              Navigator.of(context).pop();
              onMark(AttendanceStatus.absent);
            },
          ),
          const SizedBox(height: AppConstants.space8),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space16,
          vertical: AppConstants.space12,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
            color: color.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppConstants.space12),
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ───────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.isWindowOpen,
    required this.isVacationMode,
  });

  final AttendanceStatus? status;
  final bool isWindowOpen;
  final bool isVacationMode;

  @override
  Widget build(BuildContext context) {
    if (isVacationMode) return _chip('Vacation', AppColors.vacation);

    if (status == null || status == AttendanceStatus.pending) {
      return _chip(
        isWindowOpen ? 'Open' : 'Closed',
        isWindowOpen ? AppColors.secondary : AppColors.textTertiary,
      );
    }

    switch (status!) {
      case AttendanceStatus.present:
        return _chip('Present', AppColors.present);
      case AttendanceStatus.absent:
        return _chip('Absent', AppColors.absent);
      case AttendanceStatus.skipped:
        return _chip('Skipped', AppColors.skipped);
      case AttendanceStatus.onVacation:
        return _chip('Vacation', AppColors.vacation);
      case AttendanceStatus.pending:
        return _chip('Pending', AppColors.warning);
    }
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// ── Banners ────────────────────────────────────────────────────────────────────

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
          const Icon(
            Icons.beach_access_rounded,
            size: 18,
            color: AppColors.vacation,
          ),
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

class _DefaultAttendanceBanner extends StatelessWidget {
  const _DefaultAttendanceBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.space16,
        vertical: AppConstants.space12,
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
          const Icon(
            Icons.auto_awesome_rounded,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Text(
              'Auto-attendance ON — you\'re pre-marked present. Only act if absent or skipping.',
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

// ── Empty + closed notices ─────────────────────────────────────────────────────

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
              'No meals today',
              style: AppTypography.titleMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Your group has no meals scheduled\nfor today. Check back tomorrow.',
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
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
          const SizedBox(width: AppConstants.space12),
          Expanded(
            child: Text(
              'All attendance windows are closed for today. '
              'Your Admin can still update attendance manually.',
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

// ── Loading ────────────────────────────────────────────────────────────────────

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

// ── Meal image gallery ─────────────────────────────────────────────────────────

/// Horizontal scrolling thumbnail gallery shown inside a meal card when
/// the admin has attached compressed images.
///
/// Tapping a thumbnail opens a full-screen hero viewer.
class _MealImageGallery extends StatelessWidget {
  const _MealImageGallery({
    required this.imageBytes,
    required this.isDark,
  });

  final List<Uint8List> imageBytes;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.space12),
      child: SizedBox(
        height: 100,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space16),
          itemCount: imageBytes.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final tag = 'meal_img_${imageBytes[i].hashCode}_$i';
            return GestureDetector(
              onTap: () => _openViewer(context, i),
              child: Hero(
                tag: tag,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    imageBytes[i],
                    width: 110,
                    height: 100,
                    fit: BoxFit.cover,
                    cacheWidth: 220,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, int initialIndex) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.88),
        barrierDismissible: true,
        pageBuilder: (context, _, _) => _ImageViewerPage(
          imageBytes: imageBytes,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }
}

// ── Full-screen image viewer ───────────────────────────────────────────────────

class _ImageViewerPage extends StatefulWidget {
  const _ImageViewerPage({
    required this.imageBytes,
    required this.initialIndex,
  });

  final List<Uint8List> imageBytes;
  final int initialIndex;

  @override
  State<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<_ImageViewerPage> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: widget.imageBytes.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) {
                return Center(
                  child: InteractiveViewer(
                    child: Image.memory(
                      widget.imageBytes[i],
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
            // Close button
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
            ),
            // Page indicator
            if (widget.imageBytes.length > 1)
              Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 24,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.imageBytes.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _current ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _current
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

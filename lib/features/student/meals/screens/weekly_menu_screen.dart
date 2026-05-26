import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/meals/providers/student_meal_provider.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/features/student/meals/widgets/meal_card.dart';
import 'package:smart_meal_management/features/student/meals/widgets/weekly_menu_grid.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/shared/widgets/app_loading_indicator.dart';

/// Student "Weekly Menu" screen — 7-day horizontal scroll with today highlighted.
///
/// Auth IDs are read from [AuthProviderScope] instead of hard-coded stubs.
/// Uses [ListenableBuilder] — no addListener/setState boilerplate.
class WeeklyMenuScreen extends StatefulWidget {
  const WeeklyMenuScreen({super.key});

  @override
  State<WeeklyMenuScreen> createState() => _WeeklyMenuScreenState();
}

class _WeeklyMenuScreenState extends State<WeeklyMenuScreen> {
  StudentMealProvider? _provider;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final user = AuthProviderScope.of(context).currentUser;
      _provider = StudentMealProvider();
      final groupId = user?.effectiveGroupIds.firstOrNull;
      if (groupId != null) {
        _provider!.load(
          organizationId: user!.organizationId,
          groupId: groupId,
        );
      }
    }
  }

  @override
  void dispose() {
    _provider?.dispose();
    super.dispose();
  }

  void _retry() {
    final user = AuthProviderScope.of(context).currentUser;
    final groupId = user?.effectiveGroupIds.firstOrNull;
    if (groupId == null) return;
    _provider?.load(
      organizationId: user!.organizationId,
      groupId: groupId,
      forceRefresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null) {
      return const Scaffold(
        body: Center(child: AppLoadingIndicator()),
      );
    }

    // Defensive gate: if admin has disabled weekly menu, show an unavailable
    // state instead of the full screen. The shell already hides the tab, but
    // this guard protects against deep-link navigation.
    final groupConfig = GroupConfigScope.maybeOf(context);
    if (groupConfig != null && !groupConfig.weeklyMenuEnabled) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: const AppEmptyState(
          icon: Icons.menu_book_outlined,
          title: 'Weekly Menu Disabled',
          subtitle: 'Your admin has turned off the weekly menu for this group.',
        ),
      );
    }

    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Scaffold(
          backgroundColor:
              isDark ? AppColors.backgroundDark : AppColors.background,
          appBar: _WeeklyMenuAppBar(
            isDark: isDark,
            isLoading: provider.isLoading,
            onRefresh: _retry,
          ),
          body: _buildBody(context, provider, isDark),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    StudentMealProvider provider,
    bool isDark,
  ) {
    if (provider.isLoading) {
      return const Center(child: AppLoadingIndicator());
    }

    if (provider.error != null) {
      return AppEmptyState(
        icon: Icons.wifi_off_rounded,
        title: 'Could not load menu',
        subtitle: provider.error,
        actionLabel: 'Retry',
        onActionTap: _retry,
      );
    }

    if (!provider.hasSchedule) {
      return const AppEmptyState(
        icon: Icons.calendar_today_rounded,
        title: 'Menu not published yet',
        subtitle: "Your admin hasn't published the weekly menu for this week.\n"
            'Check back soon — menus are usually updated before the week begins.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppConstants.space12),

        // ── Day selector strip ─────────────────────────────────────────
        WeeklyMenuGrid(
          selectedDay: provider.selectedDay,
          daysWithMeals: provider.daysWithMeals,
          onDaySelected: provider.selectDay,
        ),
        const SizedBox(height: AppConstants.space16),

        // ── Day label row ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.space16),
          child: _WeekLabel(
            selectedDay: provider.selectedDay,
            schedule: provider.schedule!,
            isDark: isDark,
          ),
        ),
        const SizedBox(height: AppConstants.space12),

        // ── Meal list ──────────────────────────────────────────────────
        Expanded(child: _buildMealList(context, provider, isDark)),
      ],
    );
  }

  Widget _buildMealList(
    BuildContext context,
    StudentMealProvider provider,
    bool isDark,
  ) {
    final daySchedule = provider.mealsForSelectedDay;
    final today = DayOfWeek.fromWeekday(DateTime.now().weekday);
    final isToday = provider.selectedDay == today;

    if (daySchedule == null || daySchedule.isEmpty) {
      return AppEmptyState(
        icon: Icons.no_meals_rounded,
        title: 'No meals planned',
        subtitle: '${provider.selectedDay.label} has no meals configured.',
        compact: true,
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => Future(() => _retry()),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppConstants.space16,
          0,
          AppConstants.space16,
          AppConstants.space32,
        ),
        itemCount: daySchedule.meals.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: AppConstants.space12),
        itemBuilder: (context, index) {
          final entry = daySchedule.meals[index];
          return MealCard(
            entry: entry,
            isToday: isToday,
            onTap: () => _openDetail(context, entry, isToday),
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, DayMealEntry entry, bool isToday) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MealDetailScreen(entry: entry, isToday: isToday),
      ),
    );
  }
}

// ── App bar ────────────────────────────────────────────────────────────────────

class _WeeklyMenuAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _WeeklyMenuAppBar({
    required this.isDark,
    required this.isLoading,
    required this.onRefresh,
  });

  final bool isDark;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(
        'Weekly Menu',
        style: AppTypography.titleLarge.copyWith(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        if (!isLoading)
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            tooltip: 'Refresh',
            onPressed: onRefresh,
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

// ── Week label ─────────────────────────────────────────────────────────────────

class _WeekLabel extends StatelessWidget {
  const _WeekLabel({
    required this.selectedDay,
    required this.schedule,
    required this.isDark,
  });

  final DayOfWeek selectedDay;
  final MealScheduleModel schedule;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isToday = selectedDay == DayOfWeek.fromWeekday(DateTime.now().weekday);
    final label = isToday ? 'Today — ${selectedDay.label}' : selectedDay.label;

    return Row(
      children: [
        Text(
          label,
          style: AppTypography.titleMedium.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (schedule.isPublished)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppConstants.chipRadius),
            ),
            child: Text(
              'Published',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Meal detail screen ─────────────────────────────────────────────────────────

/// Full detail view for a single [DayMealEntry].
class MealDetailScreen extends StatelessWidget {
  const MealDetailScreen({
    super.key,
    required this.entry,
    this.isToday = false,
  });

  final DayMealEntry entry;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          entry.name,
          style: AppTypography.titleLarge.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.space20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero banner ────────────────────────────────────────────
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: MealModel.iconBgColor(entry.order),
                borderRadius: BorderRadius.circular(AppConstants.cardRadius),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    MealModel.slotIcon(entry.slotKey),
                    size: 56,
                    color: MealModel.iconFgColor(entry.order),
                  ),
                  const SizedBox(height: AppConstants.space8),
                  Text(
                    entry.name,
                    style: AppTypography.titleSmall.copyWith(
                      color: MealModel.iconFgColor(entry.order),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.space24),

            _InfoRow(
              icon: Icons.schedule_rounded,
              label: 'Slot',
              value: entry.slotKey,
              isDark: isDark,
            ),
            const SizedBox(height: AppConstants.space20),

            // ── Menu items ─────────────────────────────────────────────
            if (entry.menuItems.isNotEmpty) ...[
              Text(
                'Menu',
                style: AppTypography.titleSmall.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.space12),
              ...entry.menuItems.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: AppConstants.space8),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppConstants.space12),
                      Text(
                        item,
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.space20),
            ],

            // ── Today notice ───────────────────────────────────────────
            if (isToday)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.space16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(AppConstants.cardRadius),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppConstants.space12),
                    Expanded(
                      child: Text(
                        'Mark your attendance from the Attendance tab.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.surfaceVariantDark
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: AppConstants.space12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

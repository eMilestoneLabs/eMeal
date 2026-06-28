import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/widgets/cached_photo.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';

/// Horizontal scrollable timeline of today's meals.
///
/// Each meal shows as a chip-like card with open/closed status indicator.
class MealTimelineCard extends StatelessWidget {
  MealTimelineCard({
    super.key,
    required this.meals,
    AttendanceStatus? Function(String mealId)? statusForMeal,
    bool Function(MealModel)? isWindowOpen,
    StudentDashboardProvider? provider,
    this.onMealTap,
    this.currentMealId,
  })  : statusForMeal =
            statusForMeal ?? (provider != null ? provider.statusForMeal : (_) => null),
        isWindowOpen =
            isWindowOpen ?? (provider != null ? provider.isWindowOpen : (MealModel _) => false);

  final List<MealModel> meals;
  final AttendanceStatus? Function(String mealId) statusForMeal;
  final bool Function(MealModel) isWindowOpen;
  final void Function(MealModel)? onMealTap;
  final String? currentMealId;

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.pagePaddingH),
        itemCount: meals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final meal = meals[i];
          final status = statusForMeal(meal.id);
          final open = isWindowOpen(meal);
          final isCurrent = meal.id == currentMealId;

          return _MealChip(
            meal: meal,
            status: status,
            isOpen: open,
            isCurrent: isCurrent,
            onTap: onMealTap != null ? () => onMealTap!(meal) : null,
          );
        },
      ),
    );
  }
}

class _MealChip extends StatelessWidget {
  const _MealChip({
    required this.meal,
    required this.status,
    required this.isOpen,
    required this.isCurrent,
    this.onTap,
  });

  final MealModel meal;
  final AttendanceStatus? status;
  final bool isOpen;
  final bool isCurrent;
  final VoidCallback? onTap;

  Color get _borderColor {
    if (isCurrent) return AppColors.primary;
    if (status == AttendanceStatus.present) return AppColors.present;
    if (status == AttendanceStatus.absent) return AppColors.absent;
    if (isOpen) return AppColors.secondary;
    return AppColors.border;
  }

  Color get _statusDotColor {
    switch (status) {
      case AttendanceStatus.present:
        return AppColors.present;
      case AttendanceStatus.absent:
        return AppColors.absent;
      case AttendanceStatus.skipped:
        return AppColors.skipped;
      case AttendanceStatus.onVacation:
        return AppColors.vacation;
      case AttendanceStatus.pending:
      case null:
        return isOpen ? AppColors.secondary : AppColors.textTertiary;
    }
  }

  String get _statusLabel {
    switch (status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.skipped:
        return 'Skipped';
      case AttendanceStatus.onVacation:
        return 'Vacation';
      case AttendanceStatus.pending:
      case null:
        return isOpen ? 'Open' : 'Closed';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = MealModel.iconBgColor(meal.order);
    final fgColor = MealModel.iconFgColor(meal.order);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor, width: isCurrent ? 2 : 1),
          boxShadow: isCurrent
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedPhoto(
                bytes: meal.displayImageBytes,
                url: meal.networkImageUrl,
                width: 36,
                height: 36,
                cacheWidth: 72,
                useThumbnail: true,
                placeholder: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(meal.icon, color: fgColor, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              meal.name,
              style: AppTypography.labelSmall.copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _statusDotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _statusLabel,
                    style: AppTypography.labelSmall.copyWith(
                      color: _statusDotColor,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

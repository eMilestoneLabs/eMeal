import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

/// Featured card showing the next upcoming or currently open meal.
///
/// Shows meal name, window, status and a CTA to mark attendance.
/// Shows "All done for today" when no upcoming meal exists.
///
/// Text and border colours are theme-aware so the card is fully legible
/// in both light mode and dark mode.
class NextMealCard extends StatelessWidget {
  const NextMealCard({
    super.key,
    this.meal,
    this.status,
    this.isWindowOpen = false,
    this.isWindowPast = false,
    this.onMarkPresent,
    this.onMarkAttendance,
    this.onSkip,
    this.onTap,
  });

  final MealModel? meal;
  final AttendanceStatus? status;
  final bool isWindowOpen;
  final bool isWindowPast;
  final VoidCallback? onMarkPresent;

  /// Alias for [onMarkPresent] — used by dashboard screen.
  final VoidCallback? onMarkAttendance;
  final VoidCallback? onSkip;

  /// Issue 3: tapping the card body (anywhere except the action buttons) opens
  /// the meal's detail screen. Null disables the tap.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (meal == null) {
      return _AllDoneCard();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = MealModel.iconBgColor(meal!.order);
    final fgColor = MealModel.iconFgColor(meal!.order);
    final isMarked = status != null && status != AttendanceStatus.pending;

    // Theme-aware colours
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final borderColor = isWindowOpen
        ? AppColors.secondary
        : (isDark ? AppColors.borderDark : AppColors.border);

    final menu = meal!.menuItems.where((e) => e.trim().isNotEmpty).toList();
    final price = meal!.price;

    // Issue 3: compact, content-sized card. The carousel previously forced a
    // tall fixed height that left large empty space when the meal was already
    // marked. This layout is single-row + optional menu/CTA so it stays short
    // and responsive, and shows price + menu (but NOT meal preferences — those
    // live on the meal detail screen).
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: borderColor,
          width: isWindowOpen ? 1.5 : 1,
        ),
        boxShadow: isWindowOpen
            ? [
                BoxShadow(
                  color: AppColors.secondary.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(meal!.icon, color: fgColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isWindowOpen
                                ? AppColors.secondary.withValues(alpha: 0.15)
                                : (isDark
                                    ? AppColors.surfaceVariantDark
                                    : AppColors.surfaceVariant),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isWindowOpen ? 'Open Now' : 'Next Meal',
                            style: AppTypography.labelSmall.copyWith(
                              color: isWindowOpen
                                  ? AppColors.secondary
                                  : textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (price != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            '₹$price',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      meal!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall.copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TimeFormat.window12(meal!.attendanceWindow.openTime,
                          meal!.attendanceWindow.closeTime),
                      style: AppTypography.bodySmall
                          .copyWith(color: textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isMarked)
                _StatusBadge(status: status!)
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: textSecondary),
            ],
          ),
          if (menu.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.restaurant_menu_rounded,
                    size: 14, color: textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    menu.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall
                        .copyWith(color: textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (!isMarked && isWindowOpen) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: onMarkPresent ?? onMarkAttendance,
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Mark Present'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.present,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                  ),
                ),
                // SRS Module 03 (survey Q17/Q21): the quick action is
                // "Absent" (deliberate not-eating) — Skip is internal-only.
                if (onSkip != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSkip,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.absent,
                        side: BorderSide(
                            color: AppColors.absent.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: const Text('Absent'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

class _AllDoneCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.space20),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.secondary,
            size: 32,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All done for today!',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'You\'ve marked all your meals for today.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.onSecondaryContainer
                        .withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case AttendanceStatus.present:
        color = AppColors.present;
        label = 'Present';
      case AttendanceStatus.absent:
        color = AppColors.absent;
        label = 'Absent';
      case AttendanceStatus.skipped:
        color = AppColors.skipped;
        label = 'Skipped';
      case AttendanceStatus.onVacation:
        color = AppColors.vacation;
        label = 'Vacation';
      case AttendanceStatus.pending:
        color = AppColors.warning;
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
}

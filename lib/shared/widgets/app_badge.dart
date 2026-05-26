import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Small badge indicator — typically overlaid on navigation icons.
///
/// - When [count] == 0 and [showDot] is false → nothing rendered.
/// - When [showDot] is true → shows a small dot without a number.
/// - Otherwise → shows the count (capped at 99+).
///
/// The badge border adapts to the current theme brightness so it separates
/// cleanly from both light and dark scaffold backgrounds.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.child,
    this.count = 0,
    this.color,
    this.showDot = false,
    this.visible = true,
  });

  final Widget child;
  final int count;
  final Color? color;
  final bool showDot;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final show = visible && (count > 0 || showDot);
    if (!show) return child;

    final badgeColor = color ?? AppColors.absent;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Adaptive border colour — matches the scaffold background so the badge
    // "floats" above the icon in both light and dark themes.
    final borderColor =
        isDark ? AppColors.backgroundDark : AppColors.surface;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -4,
          child: showDot
              ? Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                )
              : Container(
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontSize: 9,
                      height: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      ],
    );
  }
}

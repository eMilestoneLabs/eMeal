import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Reusable empty / zero-state widget.
///
/// Shows an icon, title, optional subtitle, and optional action widget
/// (typically a button) in a centred column layout.
///
/// The icon container and text colours adapt to the active theme brightness
/// so the widget looks correct in both light and dark mode without callers
/// needing to pass explicit colours.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.actionLabel,
    this.onActionTap,
    this.iconSize = 64.0,
    this.iconColor,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final double iconSize;
  final Color? iconColor;

  /// When true, reduces padding for use in smaller containers.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final containerBg = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.surfaceVariant;
    final defaultIconColor =
        isDark ? AppColors.textTertiaryDark : AppColors.textTertiary;
    final titleColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppConstants.pagePaddingH * (compact ? 1.0 : 1.5),
          vertical: compact ? AppConstants.space16 : AppConstants.pagePaddingV,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: containerBg,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                icon,
                size: iconSize * 0.6,
                color: iconColor ?? defaultIconColor,
              ),
            ),
            const SizedBox(height: AppConstants.space20),
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(color: titleColor),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppConstants.space8),
              Text(
                subtitle!,
                style: AppTypography.bodyMedium.copyWith(color: subtitleColor),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppConstants.space24),
              action!,
            ],
            if (actionLabel != null && onActionTap != null) ...[
              const SizedBox(height: AppConstants.space16),
              TextButton(
                onPressed: onActionTap,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';

/// A compact stat / metric card for dashboards.
///
/// Displays a primary number, a label, an optional icon, and an optional
/// delta indicator (e.g. +12% vs last week).
///
/// ```dart
/// AppAnalyticsCard(
///   label: 'Present Today',
///   value: '142',
///   icon: Icons.people_rounded,
///   iconColor: AppColors.present,
///   delta: '+4%',
///   deltaPositive: true,
/// )
/// ```
class AppAnalyticsCard extends StatelessWidget {
  const AppAnalyticsCard({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.iconColor,
    this.delta,
    this.deltaPositive,
    this.onTap,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? iconColor;

  /// Change string, e.g. '+4%' or '-2 members'.
  final String? delta;

  /// Whether [delta] represents a positive change (green) or negative (red).
  /// Null means neutral (grey).
  final bool? deltaPositive;

  final VoidCallback? onTap;

  /// When true, renders a more compact layout suitable for tight grids.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = iconColor ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(
          compact ? AppConstants.space12 : AppConstants.space16,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.border,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon + delta row ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (icon != null)
                  Container(
                    width: compact ? 32 : 40,
                    height: compact ? 32 : 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: accent,
                      size: compact ? 16 : 20,
                    ),
                  ),
                if (delta != null) _DeltaBadge(delta: delta!, positive: deltaPositive),
              ],
            ),

            SizedBox(height: compact ? AppConstants.space8 : AppConstants.space12),

            // ── Value ─────────────────────────────────────────────────────────
            Text(
              value,
              style: (compact
                      ? AppTypography.numericSmall
                      : AppTypography.numericMedium)
                  .copyWith(
                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 2),

            // ── Label ─────────────────────────────────────────────────────────
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.delta, this.positive});

  final String delta;
  final bool? positive;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;

    if (positive == null) {
      color = AppColors.textTertiary;
      icon = Icons.remove_rounded;
    } else if (positive!) {
      color = AppColors.present;
      icon = Icons.arrow_upward_rounded;
    } else {
      color = AppColors.absent;
      icon = Icons.arrow_downward_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            delta,
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

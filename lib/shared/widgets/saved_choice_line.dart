import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Live-Test-16 ISSUE-5: read-only "Your choice: …" line on a marked meal so
/// the chosen options are identifiable by NAME (not colour alone) — including
/// after the attendance window has closed and the chips are gone.
class SavedChoiceLine extends StatelessWidget {
  const SavedChoiceLine({super.key, required this.text});

  /// Pre-formatted choice text, e.g. "Non-Veg: Chicken · Veg: Dal".
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.present.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.present.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.restaurant_menu_rounded,
              size: 16, color: AppColors.present),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'Your choice: ',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.present,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: text,
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

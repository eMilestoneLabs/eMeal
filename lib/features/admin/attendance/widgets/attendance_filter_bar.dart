import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// Horizontal scrollable filter chip row for attendance status filtering.
///
/// Shows chips for All, Present, Absent, Pending, Skipped.
class AttendanceFilterBar extends StatelessWidget {
  const AttendanceFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final AttendanceStatus? selected;
  final ValueChanged<AttendanceStatus?> onSelected;

  static const _options = <(String, AttendanceStatus?, Color)>[
    ('All', null, AppColors.primary),
    ('Present', AttendanceStatus.present, AppColors.present),
    ('Absent', AttendanceStatus.absent, AppColors.absent),
    ('Pending', AttendanceStatus.pending, AppColors.warning),
    ('Skipped', AttendanceStatus.skipped, AppColors.skipped),
    ('Vacation', AttendanceStatus.onVacation, AppColors.vacation),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (label, status, color) = _options[i];
          final isSelected = selected == status;
          return GestureDetector(
            onTap: () => onSelected(status),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: 0.15)
                    : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? color : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: isSelected ? color : AppColors.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// Color-coded chip widget.
///
/// Two constructors:
/// - `AppStatusChip(status: ...)` — derives label+color from [AttendanceStatus]
/// - `AppStatusChip.label(label: ..., color: ...)` — arbitrary label and color
class AppStatusChip extends StatelessWidget {
  /// Chip driven by an [AttendanceStatus] value.
  const AppStatusChip({
    super.key,
    required AttendanceStatus status,
    this.compact = false,
  })  : _status = status,
        _customLabel = null,
        _customColor = null;

  /// Chip with an arbitrary [label] and [color] (e.g. "Active", "Archived").
  const AppStatusChip.label({
    super.key,
    required String label,
    required Color color,
    this.compact = false,
  })  : _status = null,
        _customLabel = label,
        _customColor = color;

  final AttendanceStatus? _status;
  final String? _customLabel;
  final Color? _customColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (chipLabel, chipColor) = _status != null
        ? _configFromStatus(_status)
        : (_customLabel ?? '', _customColor ?? AppColors.textTertiary);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: chipColor.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 5 : 6,
            height: compact ? 5 : 6,
            decoration:
                BoxDecoration(color: chipColor, shape: BoxShape.circle),
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            chipLabel,
            style: (compact
                    ? AppTypography.labelSmall
                    : AppTypography.labelMedium)
                .copyWith(
              color: chipColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  (String, Color) _configFromStatus(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return ('Present', AppColors.present);
      case AttendanceStatus.absent:
        return ('Absent', AppColors.absent);
      case AttendanceStatus.pending:
        return ('Pending', AppColors.warning);
      case AttendanceStatus.skipped:
        return ('Skipped', AppColors.skipped);
      case AttendanceStatus.onVacation:
        return ('On Vacation', AppColors.vacation);
    }
  }
}
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// A single row in the admin attendance list.
///
/// Shows member name (or userId fallback), meal name, status chip and time.
class MemberAttendanceRow extends StatelessWidget {
  const MemberAttendanceRow({
    super.key,
    required this.record,
    this.memberName,
    this.onTap,
  });

  final AttendanceModel record;
  final String? memberName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Issue #7: prefer the joined member name from the record; fall back to any
    // explicitly supplied name, then to initials only as a last resort.
    final name = record.userName ?? memberName ?? _initials(record.userId);
    final statusColor = _statusColor(record.status);
    final statusLabel = _statusLabel(record.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primaryContainer,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Name + meal
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.mealName ?? record.mealId,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Status chip + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (record.markedAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(record.markedAt!),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String userId) {
    final parts = userId.split('_');
    return parts.last.isNotEmpty ? parts.last[0].toUpperCase() : 'U';
  }

  Color _statusColor(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return AppColors.present;
      case AttendanceStatus.absent:
        return AppColors.absent;
      case AttendanceStatus.pending:
        return AppColors.warning;
      case AttendanceStatus.skipped:
        return AppColors.skipped;
      case AttendanceStatus.onVacation:
        return AppColors.vacation;
    }
  }

  String _statusLabel(AttendanceStatus s) {
    switch (s) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.pending:
        return 'Pending';
      case AttendanceStatus.skipped:
        return 'Skipped';
      case AttendanceStatus.onVacation:
        return 'Vacation';
    }
  }

  String _formatTime(DateTime dt) =>
      TimeFormat.tod12(TimeOfDay.fromDateTime(dt));
}

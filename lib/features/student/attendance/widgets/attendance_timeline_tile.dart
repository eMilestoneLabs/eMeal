import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/record_history_sheet.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// A timeline tile for attendance history.
///
/// Shows a colored dot (status), date, meal name, and marked time.
class AttendanceTimelineTile extends StatelessWidget {
  const AttendanceTimelineTile({
    super.key,
    required this.record,
    this.isFirst = false,
    this.isLast = false,
  });

  final AttendanceModel record;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(record.status);
    final statusLabel = _statusLabel(record.status);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 32,
            child: Column(
              children: [
                if (!isFirst)
                  Expanded(
                    flex: 1,
                    child: Center(
                      child: Container(
                        width: 2,
                        color: AppColors.border,
                      ),
                    ),
                  ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.3),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Container(
                        width: 2,
                        color: AppColors.border,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              // FR-TRUST-010: tapping a record opens its full change history.
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: record.id.isEmpty
                    ? null
                    : () =>
                        RecordHistorySheet.show(context, recordId: record.id),
                child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.mealName ?? record.mealId,
                            style: AppTypography.titleSmall
                                .copyWith(color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(record.date),
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          // FR-TRUST-002: system-default records are clearly
                          // flagged — never silently indistinguishable from a
                          // member's own tap.
                          if (record.isSystemDefault) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.warning.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Auto-marked (group policy)',
                                style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
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
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
        return 'On Vacation';
    }
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatTime(DateTime d) =>
      TimeFormat.tod12(TimeOfDay.fromDateTime(d));
}

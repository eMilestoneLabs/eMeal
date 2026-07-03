import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// SRS FR-TRUST-010 (Pass 7) — member-visible change history for one
/// attendance record: WHO set/changed it (you / an admin by name / group
/// policy / verified scan), when, the resulting status and any reason. No
/// change to billable data is hidden from the member.
class RecordHistorySheet extends StatefulWidget {
  const RecordHistorySheet({super.key, required this.recordId});

  final String recordId;

  static Future<void> show(BuildContext context, {required String recordId}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordHistorySheet(recordId: recordId),
    );
  }

  @override
  State<RecordHistorySheet> createState() => _RecordHistorySheetState();
}

class _RecordHistorySheetState extends State<RecordHistorySheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _payload;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result =
        await AttendanceRepository().getRecordHistory(recordId: widget.recordId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _payload = value;
        case Err(:final failure):
          _error = failure.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final history = (_payload?['history'] as List?) ?? const [];
    final record = _payload?['record'] as Map<String, dynamic>?;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.history_rounded,
                  size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                'Record history',
                style: AppTypography.titleMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Every change to this record — nothing is hidden.',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _error!,
                style:
                    AppTypography.bodyMedium.copyWith(color: AppColors.absent),
              ),
            )
          else ...[
            if (record != null && record['source'] == 'system_default')
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'This record was created automatically by your group’s '
                  'opt-out policy. If you didn’t eat, request a correction — '
                  'it’s approved without admin friction.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No change history recorded yet.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final e = history[i] as Map<String, dynamic>;
                    return _HistoryEntryTile(entry: e);
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _HistoryEntryTile extends StatelessWidget {
  const _HistoryEntryTile({required this.entry});

  final Map<String, dynamic> entry;

  IconData get _icon => switch (entry['actorKind']) {
        'self' => Icons.person_rounded,
        'admin' => Icons.admin_panel_settings_rounded,
        'system' => Icons.smart_toy_rounded,
        'verified' => Icons.verified_rounded,
        _ => Icons.edit_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final at = DateTime.tryParse(entry['at']?.toString() ?? '')?.toLocal();
    final status = entry['status']?.toString();
    final reason = entry['reason']?.toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry['actorName'] ?? 'Unknown'}'
                  '${status != null ? ' → $status' : ''}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    reason,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
                if (at != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${at.day.toString().padLeft(2, '0')}/'
                    '${at.month.toString().padLeft(2, '0')}/${at.year} · '
                    '${at.hour.toString().padLeft(2, '0')}:'
                    '${at.minute.toString().padLeft(2, '0')}',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/billing_periods_repository.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// SRS FR-DISP-010 (Pass 7) — admin sheet to finalize (lock) the currently
/// selected billing range and manage existing periods (controlled reopen /
/// re-finalize). While a period is finalized the backend rejects every
/// attendance/billing write inside it, so statements can never change
/// silently after close (LOOP-014).
class BillingPeriodsSheet extends StatefulWidget {
  const BillingPeriodsSheet({
    super.key,
    required this.groupId,
    required this.from,
    required this.to,
  });

  final String groupId;
  final DateTime from;
  final DateTime to;

  static Future<void> show(
    BuildContext context, {
    required String groupId,
    required DateTime from,
    required DateTime to,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          BillingPeriodsSheet(groupId: groupId, from: from, to: to),
    );
  }

  @override
  State<BillingPeriodsSheet> createState() => _BillingPeriodsSheetState();
}

class _BillingPeriodsSheetState extends State<BillingPeriodsSheet> {
  final BillingPeriodsRepository _repo = BillingPeriodsRepository();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _periods = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await _repo.list(groupId: widget.groupId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Ok(:final value):
          _periods = value;
          _error = null;
        case Err(:final failure):
          _error = failure.message;
      }
    });
  }

  Future<void> _run(Future<Result<Map<String, dynamic>>> Function() op) async {
    setState(() => _busy = true);
    final result = await op();
    if (!mounted) return;
    switch (result) {
      case Ok():
        setState(() => _busy = false);
        await _load();
      case Err(:final failure):
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
  }

  Future<void> _reopen(String periodId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reopen period'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Reason (required, audited)',
            hintText: 'e.g. approved late correction for Riya, 12 Jun lunch',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Reopen'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await _run(() => _repo.reopen(periodId: periodId, reason: reason));
  }

  String _fmtRange(Map<String, dynamic> p) =>
      '${p['periodStart']} → ${p['periodEnd']}';

  @override
  Widget build(BuildContext context) {
    final fmt =
        '${widget.from.day}/${widget.from.month}/${widget.from.year} – '
        '${widget.to.day}/${widget.to.month}/${widget.to.year}';

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
              const Icon(Icons.lock_clock_rounded,
                  size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('Billing periods',
                  style: AppTypography.titleMedium
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Finalizing locks all attendance and billing changes for the '
            'period. Post-lock corrections need an audited reopen.',
            style:
                AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || _loading
                  ? null
                  : () => _run(() => _repo.finalize(
                        groupId: widget.groupId,
                        from: widget.from,
                        to: widget.to,
                      )),
              icon: const Icon(Icons.lock_rounded, size: 18),
              label: Text('Finalize selected range ($fmt)'),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const AppSheetSkeleton(rows: 3, rowHeight: 64)
          else if (_error != null)
            Text(_error!,
                style:
                    AppTypography.bodyMedium.copyWith(color: AppColors.absent))
          else if (_periods.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No finalized periods yet for this group.',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _periods.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final p = _periods[i];
                  final finalized = p['status'] == 'finalized';
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          finalized
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded,
                          size: 18,
                          color: finalized
                              ? AppColors.present
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_fmtRange(p),
                                  style: AppTypography.bodyMedium.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                finalized
                                    ? 'Finalized — writes locked'
                                    : 'Reopened: ${p['reopenReason'] ?? ''}',
                                style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSecondary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => finalized
                                  ? _reopen(p['id'].toString())
                                  : _run(() => _repo.refinalize(
                                      periodId: p['id'].toString())),
                          child: Text(finalized ? 'Reopen' : 'Re-lock'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

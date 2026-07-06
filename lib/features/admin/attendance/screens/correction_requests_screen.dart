import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/name_display.dart';
import 'package:smart_meal_management/data/repositories/correction_repository.dart';
import 'package:smart_meal_management/shared/models/correction_request_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Module 33 — Admin "Correction Requests" queue (FR-ACR-010, ISSUE-17).
///
/// Members raise post-window attendance corrections (e.g. "I ate — mark me
/// Present"); admins Approve (change applies + bills) or Reject (nothing
/// changes). Liability-decreasing corrections auto-approve server-side, so
/// this queue is mostly claim-Present reviews. Mirrors VacationRequestsScreen.
class CorrectionRequestsScreen extends StatefulWidget {
  const CorrectionRequestsScreen({super.key});

  @override
  State<CorrectionRequestsScreen> createState() =>
      _CorrectionRequestsScreenState();
}

class _CorrectionRequestsScreenState extends State<CorrectionRequestsScreen> {
  final _repo = CorrectionRepository();

  bool _loading = true;
  String? _error;
  String? _busyId;
  String _filter = 'pending';
  List<CorrectionRequestModel> _items = [];

  static const _filters = [
    'pending',
    'approved',
    'rejected',
    'expired',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _repo.list(status: _filter);
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _items = value.data;
          _loading = false;
        });
      case Err(:final failure):
        setState(() {
          _error = failure.message;
          _loading = false;
        });
    }
  }

  Future<void> _act(
    CorrectionRequestModel r,
    Future<Result<CorrectionRequestModel>> Function() action,
    String successLabel,
  ) async {
    if (_busyId != null) return;
    setState(() => _busyId = r.id);
    final res = await action();
    if (!mounted) return;
    setState(() => _busyId = null);
    switch (res) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successLabel)),
        );
        _load();
      case Err(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
    }
  }

  Future<String?> _askNote(String title) async {
    final ctrl = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLength: 200,
          decoration: const InputDecoration(
            hintText: 'Optional note (visible to the member)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Correction Requests', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Status filter ──────────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _filters[i];
                final sel = _filter == f;
                final c = _statusColor(f);
                return ChoiceChip(
                  label: Text(f[0].toUpperCase() + f.substring(1)),
                  selected: sel,
                  selectedColor: c.withValues(alpha: 0.18),
                  labelStyle: AppTypography.labelMedium.copyWith(
                    color: sel ? c : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                  onSelected: (_) {
                    setState(() => _filter = f);
                    _load();
                  },
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const AppListSkeleton(rows: 5, rowHeight: 104)
                : _error != null
                    ? _info(isDark, _error!, AppColors.error, onRetry: _load)
                    : _items.isEmpty
                        ? _info(
                            isDark,
                            'No $_filter requests.',
                            AppColors.textSecondary,
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                              itemCount: _items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) =>
                                  _card(_items[i], isDark),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _card(CorrectionRequestModel r, bool isDark) {
    final busy = _busyId == r.id;
    final c = _statusColor(r.status);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  displayMemberName(r.userName),
                  style: AppTypography.titleSmall
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  r.status[0].toUpperCase() + r.status.substring(1),
                  style: AppTypography.labelSmall
                      .copyWith(color: c, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.restaurant_rounded,
                  size: 15, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${r.typeLabel} · ${r.mealName ?? 'Meal'} · ${_fmt(r.attendanceDate)}',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
          if (r.isMemberConfirmation) ...[
            const SizedBox(height: 6),
            Text(
              'Awaiting the member’s confirmation (admin-proposed increase)',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.warning),
            ),
          ],
          if (r.reason != null && r.reason!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.reason!,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (r.reviewNote != null && r.reviewNote!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Note: ${r.reviewNote!}',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
          if (_actionsFor(r).isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  ..._actionsFor(r),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _actionsFor(CorrectionRequestModel r) {
    // Member confirmations are decided by the MEMBER, never here (FR-OVR-020).
    if (r.isPending && !r.isMemberConfirmation) {
      return [
        _btn('Approve', AppColors.present, () {
          _act(r, () => _repo.approve(r.id),
              'Approved — the record has been updated.');
        }),
        const SizedBox(width: 8),
        _btn('Reject', AppColors.absent, () async {
          final note = await _askNote('Reject request');
          await _act(r, () => _repo.reject(r.id, note: note),
              'Request rejected — nothing changed.');
        }, outlined: true),
      ];
    }
    return const [];
  }

  Widget _btn(String label, Color color, VoidCallback onTap,
      {bool outlined = false}) {
    if (outlined) {
      return Expanded(
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
          child: Text(label),
        ),
      );
    }
    return Expanded(
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _info(bool isDark, String msg, Color color, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              msg,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: color),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static Color _statusColor(String s) => switch (s) {
        'pending' => AppColors.warning,
        'approved' => AppColors.present,
        'rejected' => AppColors.absent,
        'expired' => AppColors.textTertiary,
        _ => AppColors.textSecondary,
      };
}

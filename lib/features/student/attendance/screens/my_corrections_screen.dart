import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/correction_repository.dart';
import 'package:smart_meal_management/features/student/attendance/widgets/correction_request_sheet.dart';
import 'package:smart_meal_management/shared/models/correction_request_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Module 33 — Student "My Corrections" screen (FR-ACR-001/011, FR-OVR-020).
///
/// Shows the member's own correction requests newest-first. Admin-proposed
/// confirmations ("the admin says you ate lunch — confirm?") surface with
/// Confirm / Decline actions; the member's own pending requests can be
/// cancelled. A new request can be raised for any meal within the backfill
/// window via the + button.
class MyCorrectionsScreen extends StatefulWidget {
  const MyCorrectionsScreen({super.key, this.meals = const []});

  /// The group's meal catalogue — used by the new-request sheet.
  final List<MealModel> meals;

  @override
  State<MyCorrectionsScreen> createState() => _MyCorrectionsScreenState();
}

class _MyCorrectionsScreenState extends State<MyCorrectionsScreen> {
  final _repo = CorrectionRepository();

  bool _loading = true;
  String? _error;
  String? _busyId;
  List<CorrectionRequestModel> _items = [];

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
    final res = await _repo.list();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          // Pending admin prompts first (the member must decide), then rest —
          // the server already returns newest-first within each.
          final items = value.data;
          items.sort((a, b) {
            final ap = a.isPending && a.isMemberConfirmation ? 0 : 1;
            final bp = b.isPending && b.isMemberConfirmation ? 0 : 1;
            return ap.compareTo(bp);
          });
          _items = items;
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

  Future<void> _newRequest() async {
    final created = await showCorrectionRequestSheet(
      context,
      meals: widget.meals,
    );
    if (!mounted || created == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(created.isApproved
            ? 'Applied — your record has been corrected.'
            : 'Request sent — awaiting admin review.'),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('My Corrections', style: AppTypography.titleLarge),
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
      floatingActionButton: widget.meals.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _newRequest,
              icon: const Icon(Icons.rule_rounded),
              label: const Text('New request'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _info(_error!, AppColors.error, onRetry: _load)
              : _items.isEmpty
                  ? _info(
                      'No correction requests yet.\nUse "Request correction" on a '
                      'closed meal when you ate but could not mark in time.',
                      AppColors.textSecondary,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, i) => _card(_items[i], isDark),
                      ),
                    ),
    );
  }

  Widget _card(CorrectionRequestModel r, bool isDark) {
    final busy = _busyId == r.id;
    final c = _statusColor(r.status);
    final isPrompt = r.isMemberConfirmation && r.isPending;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrompt
              ? AppColors.warning.withValues(alpha: 0.6)
              : (isDark ? AppColors.borderDark : AppColors.border)
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
                  '${r.mealName ?? 'Meal'} · ${_fmt(r.attendanceDate)}',
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
          const SizedBox(height: 6),
          Text(
            isPrompt
                ? 'Your admin says you attended this meal. Confirm to accept '
                    'the charge — decline if you did not eat.'
                : r.typeLabel,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textSecondary),
          ),
          if (r.reason != null && r.reason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              r.reason!,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
          if (r.reviewNote != null && r.reviewNote!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Note: ${r.reviewNote!}',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ],
          if (busy) ...[
            const SizedBox(height: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ] else if (isPrompt) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _act(
                      r,
                      () => _repo.confirm(r.id),
                      'Confirmed — your attendance has been recorded.',
                    ),
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.present),
                    child: const Text('Confirm — I ate'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _act(
                      r,
                      () => _repo.decline(r.id),
                      'Declined — nothing was charged.',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.absent,
                      side: BorderSide(
                          color: AppColors.absent.withValues(alpha: 0.5)),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
              ],
            ),
          ] else if (r.isPending) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _act(
                  r,
                  () => _repo.cancel(r.id),
                  'Request cancelled.',
                ),
                child: const Text('Cancel request'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _info(String msg, Color color, {VoidCallback? onRetry}) {
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

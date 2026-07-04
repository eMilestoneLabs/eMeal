import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/billing_periods_repository.dart';
import 'package:smart_meal_management/shared/models/billing_summary.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Pass 12 (SRS FR-BILLX-030/031/033, LOOP-010) — append-only billing ledger.
///
/// Admins post credits/refunds (decrease a member's bill, free) and view the
/// immutable history. Debits (increases) are intentionally NOT offered here:
/// the consent path (member correction request) is the only way a bill grows —
/// the backend enforces it (403 CONSENT_REQUIRED), the UI simply doesn't
/// pretend otherwise.
class BillingAdjustmentsSheet extends StatefulWidget {
  const BillingAdjustmentsSheet({
    super.key,
    required this.groupId,
    required this.members,
    this.onChanged,
  });

  final String groupId;
  final List<BillingMemberRow> members;
  final VoidCallback? onChanged;

  static Future<void> show(
    BuildContext context, {
    required String groupId,
    required List<BillingMemberRow> members,
    VoidCallback? onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BillingAdjustmentsSheet(
        groupId: groupId,
        members: members,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<BillingAdjustmentsSheet> createState() =>
      _BillingAdjustmentsSheetState();
}

class _BillingAdjustmentsSheetState extends State<BillingAdjustmentsSheet> {
  final _repo = BillingPeriodsRepository();
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _type = 'credit';
  String? _userId;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    if (widget.members.isNotEmpty) _userId = widget.members.first.userId;
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _repo.listAdjustments(groupId: widget.groupId);
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _entries = value;
          _loading = false;
        });
      case Err(:final failure):
        setState(() {
          _error = failure.message;
          _loading = false;
        });
    }
  }

  Future<void> _submit() async {
    final userId = _userId;
    final rupees = double.tryParse(_amountCtrl.text.trim());
    final reason = _reasonCtrl.text.trim();
    if (userId == null || rupees == null || rupees <= 0 || reason.isEmpty) {
      setState(() =>
          _error = 'Pick a member, a positive amount and a reason.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await _repo.createAdjustment(
      groupId: widget.groupId,
      userId: userId,
      type: _type,
      amountPaise: (rupees * 100).round(),
      reason: reason,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (res) {
      case Ok():
        _amountCtrl.clear();
        _reasonCtrl.clear();
        widget.onChanged?.call();
        _load();
      case Err(:final failure):
        setState(() => _error = failure.message);
    }
  }

  String _memberName(String userId) {
    for (final m in widget.members) {
      if (m.userId == userId) return m.userName;
    }
    return userId;
  }

  static String _rs(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Billing Adjustments',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Append-only ledger: every correction is a new entry — charges '
              'are never edited or deleted. Bill increases need the member\'s '
              'approved correction request.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),

            // ── Create ────────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              initialValue: _userId,
              decoration: const InputDecoration(
                labelText: 'Member',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in widget.members)
                  DropdownMenuItem(value: m.userId, child: Text(m.userName)),
              ],
              onChanged: (v) => setState(() => _userId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Credit'),
                  selected: _type == 'credit',
                  onSelected: (_) => setState(() => _type = 'credit'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Refund'),
                  selected: _type == 'refund',
                  onSelected: (_) => setState(() => _type = 'refund'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _type == 'refund'
                        ? 'Money returned for a paid charge'
                        : 'Reduces the member\'s bill',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonCtrl,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Reason (required — visible in the audit trail)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style:
                      AppTypography.bodySmall.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: 8),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_card_rounded),
                label: Text(_saving ? 'Posting…' : 'Post adjustment'),
              ),
            ),
            const SizedBox(height: 20),

            // ── History ───────────────────────────────────────────────────
            Text('Ledger (newest first)',
                style: AppTypography.titleSmall
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ))
            else if (_entries.isEmpty)
              Text('No adjustments yet.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary))
            else
              ..._entries.map((e) {
                final type = (e['type'] ?? '').toString();
                final isDebit = type == 'debit';
                final amount = (e['amount'] as num?) ?? 0;
                final c = isDebit ? AppColors.warning : AppColors.present;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_memberName((e['userId'] ?? '').toString())} · ${e['entryDate'] ?? ''}',
                              style: AppTypography.bodySmall
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text((e['reason'] ?? '').toString(),
                                style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Text(
                        '${isDebit ? '+' : '−'}${_rs(amount)}',
                        style: AppTypography.bodyMedium
                            .copyWith(color: c, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

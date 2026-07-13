import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/billing_periods_repository.dart';
import 'package:smart_meal_management/shared/models/billing_summary.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Pass 12 (SRS FR-BILLX-030/031/033, LOOP-010) — append-only billing ledger.
///
/// Admins post credits (money received — decreases the bill), refunds
/// (REF-001: cash returned to the member — consumes credit, increases the
/// outstanding bill, hard-capped server-side at the available credit) and
/// propose debits (command_6 survey 2026-07-13: the member gets a bell
/// notification and the charge bills only after THEY approve — consent
/// asymmetry in workflow form).
///
/// Issue 7: premium Material-3 redesign — searchable avatar member selector,
/// high-contrast Credit/Refund segmented control, currency-formatted amount,
/// live validation with a disabled-until-valid action, and colour-coded
/// expandable ledger cards. Fully themed for light + dark.
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
  final Set<String> _expanded = {};

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

  bool get _canSubmit {
    final amt = double.tryParse(_amountCtrl.text.trim());
    return !_saving &&
        _userId != null &&
        amt != null &&
        amt > 0 &&
        _reasonCtrl.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    final userId = _userId;
    final rupees = double.tryParse(_amountCtrl.text.trim());
    final reason = _reasonCtrl.text.trim();
    if (userId == null || rupees == null || rupees <= 0 || reason.isEmpty) {
      setState(() => _error = 'Pick a member, a positive amount and a reason.');
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.present,
              content: Text(_type == 'debit'
                  ? 'Charge of ${_rs((rupees * 100).round())} proposed — '
                      'waiting for member approval'
                  : '${_type == 'refund' ? 'Refund' : 'Credit'} '
                      'of ${_rs((rupees * 100).round())} posted'),
            ),
          );
        }
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

  BillingMemberRow? _memberById(String? userId) {
    if (userId == null) return null;
    for (final m in widget.members) {
      if (m.userId == userId) return m;
    }
    return null;
  }

  static String _rs(num paise) => '₹${(paise / 100).toStringAsFixed(2)}';

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  static String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    return '$h:$mm ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final textPrimary = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : AppColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Billing Adjustments',
                          style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w800, color: textPrimary)),
                      Text('Append-only ledger',
                          style: AppTypography.labelSmall
                              .copyWith(color: textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Every correction is a new immutable entry — charges are never '
              'edited or deleted. Bill increases need the member\'s approved '
              'correction request.',
              style: AppTypography.bodySmall.copyWith(color: textSecondary),
            ),
            const SizedBox(height: 18),

            // ── Compose card ────────────────────────────────────────────────
            _card(
              isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Member', textSecondary),
                  const SizedBox(height: 6),
                  _memberSelector(isDark, textPrimary, textSecondary),
                  const SizedBox(height: 16),
                  _label('Type', textSecondary),
                  const SizedBox(height: 6),
                  _typeSelector(isDark, textSecondary),
                  const SizedBox(height: 16),
                  _label('Amount', textSecondary),
                  const SizedBox(height: 6),
                  _amountField(isDark, textPrimary),
                  const SizedBox(height: 16),
                  _label('Reason', textSecondary),
                  const SizedBox(height: 6),
                  _reasonField(isDark, textPrimary),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _errorBanner(_error!),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.35),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _canSubmit ? _submit : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_card_rounded, size: 20),
                      label: Text(_saving ? 'Posting…' : 'Post adjustment',
                          style: AppTypography.labelLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ── Ledger ──────────────────────────────────────────────────────
            Row(
              children: [
                Text('Ledger',
                    style: AppTypography.titleSmall.copyWith(
                        fontWeight: FontWeight.w800, color: textPrimary)),
                const SizedBox(width: 8),
                Text('newest first',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textTertiary)),
                const Spacer(),
                if (_entries.isNotEmpty)
                  Text('${_entries.length} entr${_entries.length == 1 ? 'y' : 'ies'}',
                      style: AppTypography.labelSmall
                          .copyWith(color: textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              _ledgerLoading(isDark, surface)
            else if (_entries.isEmpty)
              _emptyLedger(isDark, textSecondary)
            else
              ..._entries.map((e) => _ledgerCard(isDark, e, textPrimary,
                  textSecondary)),
          ],
        ),
      ),
    );
  }

  // ── Building blocks ────────────────────────────────────────────────────────

  Widget _card(bool isDark, {required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: (isDark ? AppColors.borderDark : AppColors.border)
                  .withValues(alpha: 0.6)),
        ),
        child: child,
      );

  Widget _label(String text, Color color) => Text(
        text.toUpperCase(),
        style: AppTypography.labelSmall.copyWith(
            color: color, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      );

  Widget _avatar(String name, {double size = 36}) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(initial,
          style: AppTypography.titleSmall.copyWith(
              color: AppColors.primary, fontWeight: FontWeight.w800)),
    );
  }

  Widget _memberSelector(bool isDark, Color textPrimary, Color textSecondary) {
    final m = _memberById(_userId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.members.isEmpty ? null : _pickMember,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: (isDark ? AppColors.borderDark : AppColors.border)
                    .withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              _avatar(m?.userName ?? '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  m?.userName ?? 'Select a member',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                      color: m == null ? textSecondary : textPrimary,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.unfold_more_rounded, color: textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMember() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberPicker(
        members: widget.members,
        selectedId: _userId,
      ),
    );
    if (picked != null && mounted) setState(() => _userId = picked);
  }

  Widget _typeSelector(bool isDark, Color textSecondary) {
    Widget seg(String value, String label, IconData icon, Color accent) {
      final sel = _type == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _type = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: sel ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: sel
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: sel ? Colors.white : textSecondary),
                const SizedBox(width: 6),
                Text(label,
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : textSecondary,
                    )),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: (isDark ? AppColors.borderDark : AppColors.border)
                    .withValues(alpha: 0.7)),
          ),
          child: Row(
            children: [
              seg('credit', 'Credit', Icons.savings_rounded, AppColors.present),
              const SizedBox(width: 4),
              seg('refund', 'Refund', Icons.currency_exchange_rounded,
                  AppColors.info),
              const SizedBox(width: 4),
              // command_6 (survey 2026-07-13): debit proposes a charge that
              // the member must approve from their bell before it bills.
              seg('debit', 'Debit', Icons.trending_up_rounded,
                  AppColors.warning),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          switch (_type) {
            // REF-001: a refund returns money and CONSUMES the member's
            // credit — the outstanding bill goes UP, never down.
            'refund' =>
              'Cash returned to the member — consumes their credit '
                  '(cannot exceed the available credit).',
            'debit' =>
              'Proposed extra charge — the member gets a bell notification '
                  'and it bills only after they approve.',
            _ => 'Money received from the member (advance/goodwill) — '
                'reduces the bill.',
          },
          style: AppTypography.labelSmall.copyWith(color: textSecondary),
        ),
      ],
    );
  }

  Widget _amountField(bool isDark, Color textPrimary) {
    return TextField(
      controller: _amountCtrl,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: AppTypography.titleMedium
          .copyWith(color: textPrimary, fontWeight: FontWeight.w700),
      decoration: _inputDecoration(isDark, hint: '0.00').copyWith(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Text('₹',
              style: AppTypography.titleMedium.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w800)),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  Widget _reasonField(bool isDark, Color textPrimary) {
    return TextField(
      controller: _reasonCtrl,
      onChanged: (_) => setState(() {}),
      maxLength: 300,
      maxLines: 2,
      minLines: 1,
      style: AppTypography.bodyMedium.copyWith(color: textPrimary),
      decoration: _inputDecoration(
        isDark,
        hint: 'Required — visible in the audit trail',
      ),
    );
  }

  InputDecoration _inputDecoration(bool isDark, {required String hint}) {
    final border = (isDark ? AppColors.borderDark : AppColors.border);
    OutlineInputBorder mk(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.bodyMedium
          .copyWith(color: AppColors.textTertiary),
      filled: true,
      fillColor: isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: mk(border.withValues(alpha: 0.7), 1),
      focusedBorder: mk(AppColors.primary, 1.6),
      border: mk(border, 1),
    );
  }

  Widget _errorBanner(String msg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.error)),
            ),
          ],
        ),
      );

  Widget _ledgerCard(bool isDark, Map<String, dynamic> e, Color textPrimary,
      Color textSecondary) {
    final id = (e['id'] ?? '').toString();
    final type = (e['type'] ?? '').toString();
    final isDebit = type == 'debit';
    final amount = (e['amount'] as num?) ?? 0;
    // REF-001 (2026-07-13): refund consumes credit → increases the bill like
    // a debit; only credit decreases it.
    final increasesBill = type != 'credit';
    final status = (e['status'] ?? 'posted').toString();
    final accent = isDebit
        ? AppColors.warning
        : type == 'refund'
            ? AppColors.info
            : AppColors.present;
    final expanded = _expanded.contains(id);
    final createdBy = (e['createdBy'] ?? '').toString();
    final adminName = _memberName(createdBy);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() =>
              expanded ? _expanded.remove(id) : _expanded.add(id)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        isDebit
                            ? Icons.trending_up_rounded
                            : type == 'refund'
                                ? Icons.currency_exchange_rounded
                                : Icons.savings_rounded,
                        color: accent,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_memberName((e['userId'] ?? '').toString()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _typeChip(type, accent),
                              if (status == 'pending') ...[
                                const SizedBox(width: 6),
                                _typeChip('awaiting approval', AppColors.warning),
                              ] else if (status == 'rejected') ...[
                                const SizedBox(width: 6),
                                _typeChip('declined', AppColors.error),
                              ],
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '${_fmtDate(e['entryDate']?.toString())}'
                                  '${_fmtTime(e['createdAt']?.toString()).isNotEmpty ? ' · ${_fmtTime(e['createdAt']?.toString())}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.labelSmall
                                      .copyWith(color: textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${increasesBill ? '+' : '−'}${_rs(amount)}',
                            style: AppTypography.titleSmall.copyWith(
                                color: accent, fontWeight: FontWeight.w800)),
                        Icon(
                          expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          color: AppColors.textTertiary,
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 10),
                  Divider(
                      height: 1,
                      color: (isDark ? AppColors.borderDark : AppColors.border)
                          .withValues(alpha: 0.6)),
                  const SizedBox(height: 10),
                  _detailRow('Reason', (e['reason'] ?? '—').toString(),
                      textPrimary, textSecondary),
                  _detailRow(
                      'Posted by',
                      createdBy.isEmpty
                          ? 'Administrator'
                          : (adminName == createdBy
                              ? 'Administrator'
                              : adminName),
                      textPrimary,
                      textSecondary),
                  _detailRow('Entry date',
                      _fmtDate(e['entryDate']?.toString()), textPrimary,
                      textSecondary),
                  if (_fmtTime(e['createdAt']?.toString()).isNotEmpty)
                    _detailRow('Recorded at',
                        _fmtTime(e['createdAt']?.toString()), textPrimary,
                        textSecondary),
                  if (status != 'posted')
                    _detailRow(
                        'Status',
                        status == 'pending'
                            ? 'Awaiting member approval — not billed yet'
                            : 'Declined by member — never billed',
                        textPrimary,
                        textSecondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeChip(String type, Color accent) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          type.isEmpty ? '—' : '${type[0].toUpperCase()}${type.substring(1)}',
          style: AppTypography.labelSmall
              .copyWith(color: accent, fontWeight: FontWeight.w700),
        ),
      );

  Widget _detailRow(
      String label, String value, Color textPrimary, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: AppTypography.labelSmall.copyWith(color: textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: AppTypography.bodySmall.copyWith(
                    color: textPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _emptyLedger(bool isDark, Color textSecondary) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: (isDark ? AppColors.borderDark : AppColors.border)
                  .withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 34, color: AppColors.textTertiary.withValues(alpha: 0.6)),
            const SizedBox(height: 10),
            Text('No adjustments yet',
                style: AppTypography.bodyMedium.copyWith(
                    color: textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Posted credits and refunds will appear here.',
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary)),
          ],
        ),
      );

  Widget _ledgerLoading(bool isDark, Color surface) => Column(
        children: List.generate(
          3,
          (_) => Container(
            height: 72,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: (isDark ? AppColors.borderDark : AppColors.border)
                      .withValues(alpha: 0.5)),
            ),
            child: const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        ),
      );
}

/// Searchable, avatar-enabled member picker (FR-BILLX Issue 7).
class _MemberPicker extends StatefulWidget {
  const _MemberPicker({required this.members, required this.selectedId});
  final List<BillingMemberRow> members;
  final String? selectedId;

  @override
  State<_MemberPicker> createState() => _MemberPickerState();
}

class _MemberPickerState extends State<_MemberPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.members
        : widget.members
            .where((m) =>
                m.userName.toLowerCase().contains(q) ||
                (m.email?.toLowerCase().contains(q) ?? false))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, ctrl) => Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.backgroundDark : AppColors.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _q = v),
                  style: AppTypography.bodyMedium.copyWith(color: textPrimary),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    hintText: 'Search name or email',
                    hintStyle: AppTypography.bodyMedium
                        .copyWith(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.surfaceVariantDark
                        : AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text('No members match "$_q"',
                            style: AppTypography.bodySmall
                                .copyWith(color: textSecondary)),
                      )
                    : ListView.builder(
                        controller: ctrl,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final m = list[i];
                          final sel = m.userId == widget.selectedId;
                          final initial = m.userName.trim().isNotEmpty
                              ? m.userName.trim()[0].toUpperCase()
                              : '?';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: sel
                                  ? AppColors.primary.withValues(alpha: 0.08)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              leading: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(initial,
                                    style: AppTypography.titleSmall.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w800)),
                              ),
                              title: Text(m.userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: textPrimary)),
                              subtitle: m.email != null && m.email!.isNotEmpty
                                  ? Text(m.email!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.labelSmall.copyWith(
                                          color: textSecondary))
                                  : null,
                              trailing: sel
                                  ? const Icon(Icons.check_circle_rounded,
                                      color: AppColors.primary)
                                  : null,
                              onTap: () =>
                                  Navigator.of(context).pop(m.userId),
                            ),
                          );
                        },
                      ),
              ),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
            ],
          ),
        ),
      ),
    );
  }
}

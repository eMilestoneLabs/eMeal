import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/repositories/vacation_repository.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/vacation_request_model.dart';

/// Issue 3 — Student "Request Vacation" screen.
///
/// A member submits a date-range vacation request that an admin approves or
/// rejects. Additive: the existing self-service Vacation Mode toggle still
/// works independently; this adds the approval workflow on top.
///
/// Pass 11 (FR-VACX-003): optional meal-granular boundaries — "leaving after
/// lunch" / "back before dinner". Slot chips appear only when the group's
/// meals load (best-effort); otherwise requests cover whole days, exactly the
/// previous behaviour.
class StudentVacationRequestScreen extends StatefulWidget {
  const StudentVacationRequestScreen({
    super.key,
    this.organizationId,
    this.groupId,
  });

  /// Optional group context used to load meal slots for boundary chips.
  final String? organizationId;
  final String? groupId;

  @override
  State<StudentVacationRequestScreen> createState() =>
      _StudentVacationRequestScreenState();
}

class _StudentVacationRequestScreenState
    extends State<StudentVacationRequestScreen> {
  final _repo = VacationRepository();
  final _reasonCtrl = TextEditingController();

  DateTime? _start;
  DateTime? _end;
  bool _submitting = false;
  bool _loading = true;
  String? _error;
  List<VacationRequestModel> _mine = [];

  // Pass 11 (FR-VACX-003): meal-granular boundary slots. Best-effort — the
  // chips only render when the group's meals load; null = whole day.
  List<MealModel> _slotMeals = [];
  String? _startSlot;
  String? _endSlot;

  @override
  void initState() {
    super.initState();
    _loadMine();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    final orgId = widget.organizationId;
    final groupId = widget.groupId;
    if (orgId == null || orgId.isEmpty || groupId == null || groupId.isEmpty) {
      return;
    }
    final res = await MealRepository()
        .getGroupMeals(organizationId: orgId, groupId: groupId);
    if (!mounted) return;
    if (res case Ok(:final value)) {
      final meals = value.where((m) => m.isActive).toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      // Boundary chips only make sense with 2+ distinct slots.
      final seen = <String>{};
      final distinct = meals.where((m) => seen.add(m.slotKey)).toList();
      if (distinct.length >= 2) setState(() => _slotMeals = distinct);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    setState(() => _loading = true);
    final res = await _repo.list();
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        setState(() {
          _mine = value.data;
          _loading = false;
        });
      case Err(:final failure):
        setState(() {
          _error = failure.message;
          _loading = false;
        });
    }
  }

  Future<void> _pick(bool isStart) async {
    final now = DateTime.now();
    final initial = isStart
        ? (_start ?? now)
        : (_end ?? _start ?? now.add(const Duration(days: 1)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (_start == null || _end == null) {
      setState(() => _error = 'Pick both a start and end date.');
      return;
    }
    // Premium confirmation so the member understands what vacation mode does and
    // that it only activates after an admin approves the request.
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (_) => const _VacationRequestConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await _repo.createRequest(
      startDate: _start!,
      endDate: _end!,
      reason: _reasonCtrl.text.trim(),
      // FR-VACX-003: boundary slots (null = whole day).
      startSlotKey: _startSlot,
      endSlotKey: _endSlot,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    switch (res) {
      case Ok():
        _reasonCtrl.clear();
        setState(() {
          _start = null;
          _end = null;
          _startSlot = null;
          _endSlot = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vacation request submitted.')),
        );
        _loadMine();
      case Err(:final failure):
        setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Request Vacation', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          Row(
            children: [
              Expanded(child: _dateField('Start', _start, () => _pick(true), isDark)),
              const SizedBox(width: 12),
              Expanded(child: _dateField('End', _end, () => _pick(false), isDark)),
            ],
          ),
          // FR-VACX-003: optional meal-granular boundaries.
          if (_slotMeals.isNotEmpty) ...[
            const SizedBox(height: 16),
            _slotPicker(
              'First covered meal on the start day',
              'e.g. leaving after lunch → pick Dinner',
              _startSlot,
              (v) => setState(() => _startSlot = v),
              isDark,
            ),
            const SizedBox(height: 12),
            _slotPicker(
              'Last covered meal on the end day',
              'e.g. back before dinner → pick Lunch',
              _endSlot,
              (v) => setState(() => _endSlot = v),
              isDark,
            ),
          ],
          const SizedBox(height: 16),
          Text('Reason (optional)',
              style: AppTypography.labelMedium
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'e.g. Travelling home for the week',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(backgroundColor: AppColors.vacation),
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.beach_access_rounded),
              label: Text(_submitting ? 'Submitting...' : 'Submit request'),
            ),
          ),
          const SizedBox(height: 28),
          Text('Your requests',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ))
          else if (_mine.isEmpty)
            Text('No requests yet.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary))
          else
            ..._mine.map((r) => _requestTile(r, isDark)),
        ],
      ),
    );
  }

  /// FR-VACX-003: "Whole day" + one chip per group meal slot. Premium card +
  /// high-contrast selectable chips (command_3): the old default ChoiceChips
  /// were near-invisible in both light and dark mode.
  Widget _slotPicker(
    String title,
    String hint,
    String? selected,
    ValueChanged<String?> onChanged,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: AppTypography.labelMedium
                  .copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(hint,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _slotChip(
                label: 'Whole day',
                selected: selected == null,
                onTap: () => onChanged(null),
                isDark: isDark,
              ),
              ..._slotMeals.map(
                (m) => _slotChip(
                  label: m.name,
                  selected: selected == m.slotKey,
                  onTap: () => onChanged(m.slotKey),
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// High-contrast Material-3 selectable chip. Selected = filled vacation
  /// accent + white label + check; unselected = surface + visible border +
  /// primary-text label. Readable in BOTH themes (fixes the reported bug).
  Widget _slotChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    const accent = AppColors.vacation;
    final unselectedBg =
        (isDark ? AppColors.backgroundDark : AppColors.background);
    final unselectedFg =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final unselectedBorder =
        (isDark ? AppColors.borderDark : AppColors.border);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? accent : unselectedBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : unselectedBorder,
              width: selected ? 1.5 : 1.2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppTypography.labelMedium.copyWith(
                  color: selected ? Colors.white : unselectedFg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dateField(
      String label, DateTime? value, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_rounded,
                size: 18, color: AppColors.vacation),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textSecondary)),
                Text(
                  value == null ? 'Select' : _fmt(value),
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestTile(VacationRequestModel r, bool isDark) {
    final c = switch (r.status) {
      'approved' => AppColors.present,
      'rejected' => AppColors.absent,
      'cancelled' => AppColors.textTertiary,
      _ => AppColors.warning,
    };
    final canCancel = r.isPending || r.isApproved;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${_fmt(r.startDate)}${r.startSlotKey != null ? ' (${r.startSlotKey}+)' : ''}'
                    '  →  '
                    '${_fmt(r.endDate)}${r.endSlotKey != null ? ' (till ${r.endSlotKey})' : ''}',
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                if (r.reason != null && r.reason!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(r.reason!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(r.status[0].toUpperCase() + r.status.substring(1),
                style: AppTypography.labelSmall
                    .copyWith(color: c, fontWeight: FontWeight.w700)),
          ),
          if (canCancel)
            TextButton(
              onPressed: () async {
                final res = await _repo.cancel(r.id);
                if (!mounted) return;
                if (res case Err(:final failure)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(failure.message)));
                } else {
                  _loadMine();
                }
              },
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}


// ── Premium vacation-request confirmation dialog ───────────────────────────────
//
// Reuses the original premium "Vacation Mode" dialog design (previously shown for
// the self-enable toggle). It now appears when a member SUBMITS a vacation
// request, so they understand that — once an admin approves — attendance tracking
// and meal reminders pause for the selected dates.
class _VacationRequestConfirmDialog extends StatelessWidget {
  const _VacationRequestConfirmDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(AppConstants.space24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.dialogRadius),
          border: Border.all(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.5)
                : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.vacation.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.beach_access_rounded,
                color: AppColors.vacation,
                size: 26,
              ),
            ),
            const SizedBox(height: AppConstants.space16),
            Text(
              'Submit Vacation Request?',
              style: AppTypography.titleMedium.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space8),
            Text(
              'Once your admin approves, attendance tracking and all meal '
              'reminders will be paused for the selected dates. You can turn it '
              'off early if you return.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.space24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color:
                              isDark ? AppColors.borderDark : AppColors.border,
                        ),
                        borderRadius:
                            BorderRadius.circular(AppConstants.buttonRadius),
                      ),
                      child: Center(
                        child: Text(
                          'Cancel',
                          style: AppTypography.labelMedium.copyWith(
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(true),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.vacation,
                        borderRadius:
                            BorderRadius.circular(AppConstants.buttonRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.vacation.withValues(alpha: 0.30),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          'Submit Request',
                          style: AppTypography.labelMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

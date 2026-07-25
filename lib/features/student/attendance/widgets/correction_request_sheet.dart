import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/correction_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/utils/verification_gate.dart';
import 'package:smart_meal_management/shared/models/correction_request_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/preference_group_selector.dart';

/// Module 33 (ISSUE-17) + SRS Module 03 ATT-004/COR-004/005/006: bottom sheet
/// to raise an Attendance Correction Request for a meal AFTER its window
/// closed, on the SAME calendar day only.
///
/// Types offered (COR-004 — Present or Absent only, Skip is never a target):
///   • I ate — mark me Present (claim_present → admin approves/rejects)
///   • I didn't eat — mark me Absent (correct_to_absent → admin approves/rejects)
///   • Fix my preference (fix_preference → billing-neutral, when options exist)
///
/// COR-006: when the meal has preference groups and the member requests
/// Present, the ENTIRE preference selection must be completed again with the
/// same validation as normal marking — Submit stays disabled until valid.
/// The admin only approves or rejects; the system applies the submitted
/// values automatically.
Future<CorrectionRequestModel?> showCorrectionRequestSheet(
  BuildContext context, {
  required List<MealModel> meals,
  MealModel? initialMeal,
  DateTime? initialDate,
  // Kept for call-site compatibility; COR-005 makes corrections same-day only
  // so the date is fixed and no longer pickable.
  int maxAgeDays = 0,
}) {
  if (meals.isEmpty && initialMeal == null) return Future.value(null);
  return showModalBottomSheet<CorrectionRequestModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CorrectionRequestSheet(
      meals: meals.isEmpty ? [initialMeal!] : meals,
      initialMeal: initialMeal,
      initialDate: initialDate,
    ),
  );
}

class _CorrectionRequestSheet extends StatefulWidget {
  const _CorrectionRequestSheet({
    required this.meals,
    this.initialMeal,
    this.initialDate,
  });

  final List<MealModel> meals;
  final MealModel? initialMeal;
  final DateTime? initialDate;

  @override
  State<_CorrectionRequestSheet> createState() =>
      _CorrectionRequestSheetState();
}

class _CorrectionRequestSheetState extends State<_CorrectionRequestSheet> {
  final _repo = CorrectionRepository();
  final _reasonCtrl = TextEditingController();

  late MealModel _meal;
  late DateTime _date;
  String _type = 'claim_present';
  String? _preference;
  bool _submitting = false;
  String? _error;

  // COR-006: preference-group selection state (claim_present on group meals).
  List<PreferenceSelection> _selections = const [];
  bool _selectionsComplete = true;

  @override
  void initState() {
    super.initState();
    _meal = widget.initialMeal ?? widget.meals.first;
    // COR-005: corrections are same-calendar-day only. The date is the meal's
    // ORG-timezone business date (the date the backend keyed attendance
    // under), never the device date, and it is not user-pickable.
    final base =
        widget.initialDate ?? _parseOrgDate(_meal.orgDate) ?? DateTime.now();
    _date = DateTime(base.year, base.month, base.day);
    // COR-006: a meal with REQUIRED preference groups starts incomplete until
    // the selector reports every required group satisfied (shared no-picks
    // rule — visibleWhen + fail-safe aware, Live-Test-6 ISSUE-2).
    _selectionsComplete =
        PreferenceGroupSelector.initialComplete(_meal.preferenceGroups);
  }

  /// "YYYY-MM-DD" → local-midnight DateTime; null on missing/unparsable input.
  static DateTime? _parseOrgDate(String? s) {
    if (s == null || s.length < 10) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    final d = int.tryParse(s.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _needsGroupSelections =>
      _type == 'claim_present' && _meal.preferenceGroups.isNotEmpty;

  bool get _needsFlatPreference =>
      _type == 'claim_present' &&
      _meal.preferenceGroups.isEmpty &&
      _meal.preferencesEnabled &&
      _meal.enabledPreferences.isNotEmpty;

  /// COR-006: Submit stays disabled until every mandatory selection is done —
  /// exactly the same gate as normal attendance marking.
  bool get _canSubmit {
    if (_submitting) return false;
    if (_type == 'fix_preference' && _preference == null) return false;
    if (_needsGroupSelections && !_selectionsComplete) return false;
    if (_needsFlatPreference && _preference == null) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) {
      setState(() =>
          _error = 'Complete all required meal preference selections first.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await _repo.createRequest(
      mealId: _meal.id,
      attendanceDate: _date,
      requestType: _type,
      requestedPreference: (_type == 'fix_preference' || _needsFlatPreference)
          ? _preference
          : null,
      selections: _needsGroupSelections
          ? _selections.map((s) => s.toJson()).toList()
          : null,
      reason: _reasonCtrl.text.trim(),
    );
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
        // SRS Module 03 ACC-005: unverified members get the guided verify
        // flow instead of a dead-end inline error.
        final email =
            AuthProviderScope.of(context).currentUser?.email ?? '';
        if (VerificationGate.isVerificationRequired(failure)) {
          await VerificationGate.handle(context, failure, email: email);
          if (mounted) Navigator.of(context).pop();
          return;
        }
        setState(() {
          _submitting = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    // ISSUE-008: the system "None" choice is always offered last on the
    // standalone picker ("attending, no preference item").
    final prefs = [
      ..._meal.enabledPreferences,
      if (_meal.enabledPreferences.isNotEmpty &&
          !_meal.enabledPreferences.any(MealPreferenceOption.isSystemNone))
        MealPreferenceOption.noneKey,
    ];

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Request a correction',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'An admin reviews your request. Your record (and bill) only '
              'changes if it is approved. Corrections are allowed for '
              'today only — until 11:59 PM.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppConstants.space16),

            // ── Meal + date (COR-005: date fixed to today, not pickable) ────
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _meal.id,
                    decoration: const InputDecoration(
                      labelText: 'Meal',
                      isDense: true,
                    ),
                    items: widget.meals
                        .map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Text(m.name,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (id) {
                      final m = widget.meals.where((x) => x.id == id);
                      if (m.isNotEmpty) {
                        setState(() {
                          _meal = m.first;
                          _preference = null;
                          _selections = const [];
                          _selectionsComplete =
                              PreferenceGroupSelector.initialComplete(
                                  m.first.preferenceGroups);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Chip(
                  avatar: const Icon(Icons.event_rounded, size: 16),
                  label: Text(
                    'Today · ${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}',
                    style: AppTypography.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.space12),

            // ── Request type (COR-004: Present or Absent only) ─────────────
            RadioGroup<String>(
              groupValue: _type,
              onChanged: (v) => setState(() {
                _type = v ?? _type;
                _error = null;
              }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _typeTile('claim_present', 'I ate — mark me Present',
                      'Needs admin approval; billed only after approval.'),
                  _typeTile(
                      'correct_to_absent',
                      'I didn’t eat — mark me Absent',
                      'Needs admin approval; nothing is charged if approved.'),
                  if (prefs.isNotEmpty || _meal.preferenceGroups.isNotEmpty)
                    _typeTile('fix_preference', 'Fix my preference',
                        'Billing-neutral; corrects the stored choice.'),
                ],
              ),
            ),

            // ── COR-006: full preference selection, same rules as marking ──
            if (_needsGroupSelections) ...[
              const SizedBox(height: AppConstants.space8),
              Text('Meal preferences (required)',
                  style: AppTypography.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              PreferenceGroupSelector(
                groups: _meal.preferenceGroups,
                onChanged: (selections, totalDelta, complete) {
                  setState(() {
                    _selections = selections;
                    _selectionsComplete = complete;
                  });
                },
              ),
            ],
            if ((_needsFlatPreference || _type == 'fix_preference') &&
                prefs.isNotEmpty) ...[
              const SizedBox(height: AppConstants.space8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: prefs.map((p) {
                  final sel = _preference == p;
                  // ISSUE-008: shared display resolver — 'none' renders as
                  // the system 🚫 None chip, custom tags keep their name.
                  final disp = MealPreferenceOption.display(p);
                  return ChoiceChip(
                    label: Text(disp.emoji.isEmpty
                        ? disp.label
                        : '${disp.emoji} ${disp.label}'),
                    selected: sel,
                    onSelected: (_) => setState(() => _preference = p),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: AppConstants.space12),
            TextField(
              controller: _reasonCtrl,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. I ate but forgot to mark before the window closed',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!,
                  style:
                      AppTypography.labelSmall.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppConstants.space12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit request'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeTile(String value, String title, String subtitle) {
    return RadioListTile<String>(
      value: value,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: AppTypography.bodyMedium),
      subtitle: Text(subtitle,
          style:
              AppTypography.labelSmall.copyWith(color: AppColors.textTertiary)),
    );
  }
}

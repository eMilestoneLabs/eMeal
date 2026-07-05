import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/correction_repository.dart';
import 'package:smart_meal_management/shared/models/correction_request_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Module 33 (ISSUE-17): bottom sheet to raise an Attendance Correction
/// Request for a (meal, date) after the window closed.
///
/// Types offered:
///   • I ate — mark me Present (claim_present → needs admin approval)
///   • I didn't eat — mark me Absent (correct_to_absent → auto-approvable)
///   • Mark as Skipped (correct_to_skip → auto-approvable)
///   • Fix my preference (fix_preference → billing-neutral, when options exist)
///
/// Returns the created request (null when dismissed). The caller shows the
/// outcome snackbar — an auto-approved request comes back status=approved.
Future<CorrectionRequestModel?> showCorrectionRequestSheet(
  BuildContext context, {
  required List<MealModel> meals,
  MealModel? initialMeal,
  DateTime? initialDate,
  int maxAgeDays = 7,
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
      maxAgeDays: maxAgeDays,
    ),
  );
}

class _CorrectionRequestSheet extends StatefulWidget {
  const _CorrectionRequestSheet({
    required this.meals,
    required this.maxAgeDays,
    this.initialMeal,
    this.initialDate,
  });

  final List<MealModel> meals;
  final MealModel? initialMeal;
  final DateTime? initialDate;
  final int maxAgeDays;

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

  @override
  void initState() {
    super.initState();
    _meal = widget.initialMeal ?? widget.meals.first;
    // Default the correction date to the meal's ORG-timezone business date (the
    // date the backend keyed the meal/attendance under), NOT the device date.
    // A phone calendar that differs from the org date submitted a date the
    // backend couldn't match, so the request was rejected — exactly the
    // "closed attendance → can't request" symptom. Falls back to the device
    // date only when orgDate is absent (e.g. a cache-painted meal). All of
    // today's meals share the same org date, so this stays correct if the user
    // switches meals inside the sheet.
    final base =
        widget.initialDate ?? _parseOrgDate(_meal.orgDate) ?? DateTime.now();
    _date = DateTime(base.year, base.month, base.day);
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

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: now.subtract(Duration(days: widget.maxAgeDays)),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_type == 'fix_preference' && (_preference == null)) {
      setState(() => _error = 'Choose the corrected preference first.');
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
      requestedPreference: _type == 'fix_preference' ? _preference : null,
      reason: _reasonCtrl.text.trim(),
    );
    if (!mounted) return;
    switch (res) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final failure):
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
    final prefs = _meal.enabledPreferences;

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
              'changes if it is approved.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppConstants.space16),

            // ── Meal + date ────────────────────────────────────────────────
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
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_rounded, size: 16),
                  label: Text(
                    '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.space12),

            // ── Request type ───────────────────────────────────────────────
            RadioGroup<String>(
              groupValue: _type,
              onChanged: (v) => setState(() => _type = v ?? _type),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _typeTile('claim_present', 'I ate — mark me Present',
                      'Needs admin approval; billed only after approval.'),
                  _typeTile(
                      'correct_to_absent',
                      'I didn’t eat — mark me Absent',
                      'Applied immediately (reduces your bill).'),
                  _typeTile('correct_to_skip', 'Mark as Skipped',
                      'Applied immediately (no charge).'),
                  if (prefs.isNotEmpty)
                    _typeTile('fix_preference', 'Fix my preference',
                        'Billing-neutral; corrects the stored choice.'),
                ],
              ),
            ),

            if (_type == 'fix_preference' && prefs.isNotEmpty) ...[
              const SizedBox(height: AppConstants.space8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: prefs.map((p) {
                  final sel = _preference == p;
                  return ChoiceChip(
                    label: Text(p[0].toUpperCase() + p.substring(1)),
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
                onPressed: _submitting ? null : _submit,
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

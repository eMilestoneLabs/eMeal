import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';

/// Module 22 (FR-HG-020/021, Pass 9) — hosted-guest settings editor.
///
/// Returns the edited [GroupGuestConfig] (caller persists via
/// MealConfigProvider.updateGuestConfig), or null when dismissed.
Future<GroupGuestConfig?> showGuestConfigSheet(
  BuildContext context, {
  required GroupGuestConfig config,
  required bool pricingEnabled,
}) {
  return showModalBottomSheet<GroupGuestConfig>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GuestConfigSheet(
      config: config,
      pricingEnabled: pricingEnabled,
    ),
  );
}

class _GuestConfigSheet extends StatefulWidget {
  const _GuestConfigSheet({
    required this.config,
    required this.pricingEnabled,
  });

  final GroupGuestConfig config;
  final bool pricingEnabled;

  @override
  State<_GuestConfigSheet> createState() => _GuestConfigSheetState();
}

class _GuestConfigSheetState extends State<_GuestConfigSheet> {
  late GroupGuestConfig _cfg = widget.config;

  late final TextEditingController _perMeal =
      TextEditingController(text: '${_cfg.maxGuestsPerMemberPerMeal}');
  late final TextEditingController _perDay = TextEditingController(
      text: _cfg.maxGuestsPerMemberPerDay?.toString() ?? '');
  late final TextEditingController _surcharge =
      TextEditingController(text: _cfg.guestSurcharge?.toString() ?? '');
  late final TextEditingController _cutoff = TextEditingController(
      text: '${_cfg.guestCutoffMinutesBeforeClose}');
  late final TextEditingController _advance =
      TextEditingController(text: '${_cfg.guestAdvanceBookingDays}');

  @override
  void dispose() {
    for (final c in [_perMeal, _perDay, _surcharge, _cutoff, _advance]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  void _save() {
    // Built explicitly (not copyWith) so BLANK optional fields genuinely
    // clear to null — "no daily cap" / "no per-guest price" must round-trip.
    Navigator.of(context).pop(GroupGuestConfig(
      guestAttendanceEnabled: _cfg.guestAttendanceEnabled,
      // Live-Test-16 ISSUE-4: hard ceiling (server enforces the same).
      maxGuestsPerMemberPerMeal: (_int(_perMeal) ?? _cfg.maxGuestsPerMemberPerMeal)
          .clamp(1, AppConstants.guestMaxPerMeal),
      maxGuestsPerMemberPerDay: _int(_perDay),
      guestPricingMode: _cfg.guestPricingMode,
      // Adult/child prices are no longer editable (mode retired) — the stored
      // values round-trip untouched so no database column is rewritten.
      guestAdultPrice: _cfg.guestAdultPrice,
      guestChildPrice: _cfg.guestChildPrice,
      guestSurcharge: _int(_surcharge),
      guestSurchargeType: _cfg.guestSurchargeType,
      guestRequiresApproval: _cfg.guestRequiresApproval,
      guestCutoffMinutesBeforeClose:
          (_int(_cutoff) ?? _cfg.guestCutoffMinutesBeforeClose).clamp(0, 720),
      guestAdvanceBookingDays:
          (_int(_advance) ?? _cfg.guestAdvanceBookingDays).clamp(0, 30),
      guestPreferenceRequired: _cfg.guestPreferenceRequired,
      allowGuestWithoutHost: _cfg.allowGuestWithoutHost,
      billNoShowGuests: _cfg.billNoShowGuests,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.bottomSheetRadius),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.space20,
              AppConstants.space20,
              AppConstants.space12,
              AppConstants.space8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Guest settings',
                    style: AppTypography.titleMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              // Live-Test-16 ISSUE-4: top inset so the first row's FLOATING
              // labels are never clipped by the scroll viewport edge.
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space20,
                AppConstants.space12,
                AppConstants.space20,
                AppConstants.space20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _numField(
                          _perMeal,
                          label: 'Guests / meal',
                          hint: '1–${AppConstants.guestMaxPerMeal}',
                          helper: 'Max ${AppConstants.guestMaxPerMeal}',
                        ),
                      ),
                      const SizedBox(width: AppConstants.space12),
                      Expanded(
                        child: _numField(
                          _perDay,
                          label: 'Guests / day',
                          hint: 'No limit',
                          helper: 'Blank = no daily limit',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppConstants.space12),
                  Row(
                    children: [
                      Expanded(
                        child: _numField(
                          _cutoff,
                          label: 'Cutoff (min)',
                          hint: '0',
                          helper: 'Stop before window closes',
                        ),
                      ),
                      const SizedBox(width: AppConstants.space12),
                      Expanded(
                        child: _numField(
                          _advance,
                          label: 'Book ahead (days)',
                          hint: '0',
                          helper: '0 = same day only',
                        ),
                      ),
                    ],
                  ),
                  if (widget.pricingEnabled) ...[
                    const SizedBox(height: AppConstants.space16),
                    Text(
                      'Guest pricing',
                      style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppConstants.space8),
                    DropdownButtonFormField<String>(
                      // ISSUE-4 "UI cut": long labels ellipsize instead of
                      // overflowing on narrow phones / large text scale.
                      isExpanded: true,
                      initialValue: _cfg.guestPricingMode,
                      decoration:
                          const InputDecoration(labelText: 'Pricing mode'),
                      items: const [
                        DropdownMenuItem(
                          value: 'sameAsMember',
                          child: Text('Same as member price'),
                        ),
                        DropdownMenuItem(
                          value: 'flatSurcharge',
                          child: Text('Member price + surcharge'),
                        ),
                      ],
                      onChanged: (v) => setState(() =>
                          _cfg = _cfg.copyWith(guestPricingMode: v)),
                    ),
                    const SizedBox(height: AppConstants.space12),
                    if (_cfg.guestPricingMode == 'flatSurcharge') ...[
                      // GST-011: the surcharge is Fixed ₹ OR a percentage of
                      // the final effective member price — never both.
                      DropdownButtonFormField<String>(
                        isExpanded: true, // ISSUE-4: never overflow
                        initialValue: _cfg.guestSurchargeType,
                        decoration: const InputDecoration(
                          labelText: 'Surcharge type',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'fixed',
                            child: Text('Fixed amount (₹)'),
                          ),
                          DropdownMenuItem(
                            value: 'percent',
                            child: Text('Percentage of member price (%)'),
                          ),
                        ],
                        onChanged: (v) => setState(
                            () => _cfg = _cfg.copyWith(guestSurchargeType: v)),
                      ),
                      const SizedBox(height: AppConstants.space12),
                      _numField(
                        _surcharge,
                        label: _cfg.guestSurchargeType == 'percent'
                            ? 'Surcharge per guest (%)'
                            : 'Surcharge per guest (₹)',
                        hint: _cfg.guestSurchargeType == 'percent'
                            ? '0–100, applied on final member price'
                            : 'Required',
                      ),
                    ],
                  ],
                  const SizedBox(height: AppConstants.space8),
                  _toggle(
                    'Require admin approval',
                    'Member bookings park as pending until you approve',
                    _cfg.guestRequiresApproval,
                    (v) => setState(
                        () => _cfg = _cfg.copyWith(guestRequiresApproval: v)),
                  ),
                  _toggle(
                    'Require a preference per guest',
                    'Each guest must carry a meal preference',
                    _cfg.guestPreferenceRequired,
                    (v) => setState(() =>
                        _cfg = _cfg.copyWith(guestPreferenceRequired: v)),
                  ),
                  _toggle(
                    'Allow guests without host present',
                    'Off (default): guests auto-cancel if the host is not Present',
                    _cfg.allowGuestWithoutHost,
                    (v) => setState(
                        () => _cfg = _cfg.copyWith(allowGuestWithoutHost: v)),
                  ),
                  _toggle(
                    'Bill no-show guests',
                    'Booked guests are billed even if unconsumed (LOOP-013)',
                    _cfg.billNoShowGuests,
                    (v) => setState(
                        () => _cfg = _cfg.copyWith(billNoShowGuests: v)),
                  ),
                  const SizedBox(height: AppConstants.space16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Save guest settings'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numField(
    TextEditingController controller, {
    required String label,
    required String hint,
    String? helper,
  }) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          // ISSUE-4: short labels + a one-line helper so nothing truncates in
          // the half-width fields.
          helperText: helper,
          helperMaxLines: 1,
          isDense: true,
        ),
      );

  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title, style: AppTypography.bodyMedium),
        subtitle: Text(subtitle, style: AppTypography.labelSmall),
        value: value,
        onChanged: onChanged,
      );
}

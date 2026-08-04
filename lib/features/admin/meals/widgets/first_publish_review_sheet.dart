import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';

/// Live-Test-16 ISSUE-1 — First Publication · Financial & Billing Review.
///
/// Shown ONCE per group, immediately before its FIRST meal schedule is
/// published, because that publication permanently freezes the group's
/// Meal-Pricing ON/OFF mode (`groups.firstSchedulePublishedAt` on the server).
///
/// Contract with the caller:
///   * returns `true`  → the admin reviewed, acknowledged and confirmed; the
///                       caller performs the publish.
///   * returns `false` → "Review / Change Configuration": the caller must NOT
///                       publish and should send the admin back to Meal Config.
///   * returns `null`  → dismissed. Nothing happens, nothing is consumed.
///
/// Opening, scrolling, ticking boxes or leaving this sheet locks NOTHING — the
/// lock is consumed only by a publish that actually succeeds on the server.
Future<bool?> showFirstPublishReviewSheet(
  BuildContext context, {
  required String groupName,
  required GroupMealConfig config,
  /// Performs the publish. Returns null on success, or a user-facing error
  /// message on failure — the sheet then STAYS OPEN showing that error, so a
  /// failed publish never looks like a successful one.
  required Future<String?> Function() onConfirm,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FirstPublishReviewSheet(
      groupName: groupName,
      config: config,
      onConfirm: onConfirm,
    ),
  );
}

class _FirstPublishReviewSheet extends StatefulWidget {
  const _FirstPublishReviewSheet({
    required this.groupName,
    required this.config,
    required this.onConfirm,
  });

  final String groupName;
  final GroupMealConfig config;
  final Future<String?> Function() onConfirm;

  @override
  State<_FirstPublishReviewSheet> createState() =>
      _FirstPublishReviewSheetState();
}

class _FirstPublishReviewSheetState extends State<_FirstPublishReviewSheet> {
  bool _ackPricing = false;
  bool _ackCycle = false;
  bool _ackPermanent = false;
  bool _publishing = false;
  String? _error;

  bool get _canPublish =>
      _ackPricing && _ackCycle && _ackPermanent && !_publishing;

  static String _ord(int d) {
    if (d >= 11 && d <= 13) return 'th';
    return switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
  }

  /// Null / 1 both mean "calendar month" — the server treats them identically.
  String get _cycleLabel {
    final d = widget.config.billingCycleStartDay ?? 1;
    return d <= 1
        ? '1st of every month (calendar month)'
        : '$d${_ord(d)} → ${d - 1}${_ord(d - 1)} of the next month';
  }

  Future<void> _confirm() async {
    if (!_canPublish) return;
    setState(() {
      _publishing = true;
      _error = null;
    });
    final error = await widget.onConfirm();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    // §8: the publish FAILED — nothing was locked. Stay open with the reason.
    setState(() {
      _publishing = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surface;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final pricingOn = widget.config.mealPricingEnabled;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.borderDark : AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _header(textPrimary, textSecondary),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _groupCard(isDark, textPrimary, textSecondary),
                    const SizedBox(height: 12),
                    _pricingCard(isDark, pricingOn, textPrimary, textSecondary),
                    const SizedBox(height: 12),
                    _cycleCard(isDark, textPrimary, textSecondary),
                    const SizedBox(height: 16),
                    _warningCard(isDark, pricingOn),
                    const SizedBox(height: 16),
                    Text('Please confirm',
                        style: AppTypography.labelLarge.copyWith(
                          color: textPrimary,
                          fontWeight: FontWeight.w800,
                        )),
                    const SizedBox(height: 4),
                    _ack(
                      value: _ackPricing,
                      onChanged: (v) => setState(() => _ackPricing = v),
                      label: 'I have reviewed the Meal Pricing configuration.',
                      textColor: textPrimary,
                    ),
                    _ack(
                      value: _ackCycle,
                      onChanged: (v) => setState(() => _ackCycle = v),
                      label: 'I have reviewed the Billing Cycle configuration.',
                      textColor: textPrimary,
                    ),
                    _ack(
                      value: _ackPermanent,
                      onChanged: (v) => setState(() => _ackPermanent = v),
                      label:
                          'I understand that the Billing Cycle and the Enable '
                          'Meal Pricing setting will be locked after the first '
                          'successful publish. Individual meal prices will '
                          'remain editable.',
                      textColor: textPrimary,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _errorCard(_error!),
                    ],
                  ],
                ),
              ),
            ),
            _actions(isDark, textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _header(Color textPrimary, Color textSecondary) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.verified_user_rounded,
                  color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('First Publication',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      )),
                  Text('Final Financial Configuration Review',
                      style: AppTypography.titleMedium.copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                      )),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _shell(bool isDark, {required Widget child, Color? accent}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.surfaceElevatedDark
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent ??
                (isDark ? AppColors.borderDark : AppColors.border)
                    .withValues(alpha: 0.6),
            width: accent != null ? 1.4 : 1,
          ),
        ),
        child: child,
      );

  Widget _groupCard(bool isDark, Color textPrimary, Color textSecondary) =>
      _shell(
        isDark,
        child: Row(
          children: [
            const Icon(Icons.groups_rounded,
                size: 20, color: AppColors.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Group',
                      style: AppTypography.labelSmall
                          .copyWith(color: textSecondary)),
                  Text(widget.groupName,
                      style: AppTypography.bodyLarge.copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.w700,
                      )),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _pricingCard(
    bool isDark,
    bool on,
    Color textPrimary,
    Color textSecondary,
  ) {
    final accent = on ? AppColors.secondary : AppColors.textTertiary;
    return _shell(
      isDark,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_rounded, size: 20, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Meal Pricing',
                    style: AppTypography.bodyMedium.copyWith(
                      color: textPrimary,
                      fontWeight: FontWeight.w800,
                    )),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(on ? Icons.check_circle_rounded : Icons.block_rounded,
                        size: 14, color: accent),
                    const SizedBox(width: 4),
                    Text(on ? 'ENABLED' : 'DISABLED',
                        style: AppTypography.labelSmall.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            on
                ? 'Meals carry a ₹ price. Members see prices and this group is '
                    'billed. After publishing, Meal Pricing can never be turned '
                    'off for this group — individual meal prices stay editable.'
                : 'Meals have no price and nothing is billed. After publishing, '
                    'Meal Pricing can never be turned on for this group — you '
                    'would need to create a new group instead.',
            style: AppTypography.bodySmall.copyWith(color: textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _cycleCard(bool isDark, Color textPrimary, Color textSecondary) =>
      _shell(
        isDark,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_month_rounded,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Billing Cycle',
                      style: AppTypography.bodyMedium.copyWith(
                        color: textPrimary,
                        fontWeight: FontWeight.w800,
                      )),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_cycleLabel,
                style: AppTypography.bodyMedium.copyWith(
                  color: textPrimary,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
            Text(
              // Live-Test-17 ISSUE-3: this text previously promised that
              // "publishing does not use up that change" — the exact opposite
              // of the rule this sheet now enforces. Publishing IS the event
              // that makes the cycle permanent.
              'This boundary governs every billing period and the '
              'data-retention window. You can still change it now — after this '
              'first publish it is permanently locked for this group.',
              style: AppTypography.bodySmall.copyWith(color: textSecondary),
            ),
          ],
        ),
      );

  Widget _warningCard(bool isDark, bool pricingOn) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.warning.withValues(alpha: 0.12)
              : AppColors.warningContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.55),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_clock_rounded,
                size: 20, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This decision is permanent',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark
                            ? AppColors.warning
                            : AppColors.onWarningContainer,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    'Publishing this first schedule finalises Meal Pricing as '
                    '${pricingOn ? 'ENABLED' : 'DISABLED'} AND locks the Billing '
                    'Cycle for the entire life of this group. The locks are '
                    'enforced by the server, so they cannot be undone by '
                    'reinstalling the app, clearing data, turning the meal '
                    'system off and on again, or using another device.\n\n'
                    'This does NOT lock individual meal prices. If Meal Pricing '
                    'is enabled you can keep editing and customising each '
                    'meal\'s ₹ price exactly as before.',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.warning
                          : AppColors.onWarningContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _ack({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String label,
    required Color textColor,
  }) =>
      InkWell(
        onTap: _publishing ? null : () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Checkbox(
                  value: value,
                  onChanged: _publishing ? null : (v) => onChanged(v ?? false),
                  activeColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(label,
                      style: AppTypography.bodySmall.copyWith(color: textColor)),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _errorCard(String message) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 18, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Publication failed — nothing was locked',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w800,
                      )),
                  const SizedBox(height: 2),
                  Text(message,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.error)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _actions(bool isDark, Color textSecondary) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _canPublish ? _confirm : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _publishing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_rounded, size: 18),
                label: Text(
                  _publishing
                      ? 'Publishing…'
                      : 'Confirm Configuration & Publish',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton.icon(
                // §5: never trap the admin — go back and fix the configuration.
                onPressed:
                    _publishing ? null : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Review / Change Configuration'),
                style: TextButton.styleFrom(foregroundColor: textSecondary),
              ),
            ),
          ],
        ),
      );
}

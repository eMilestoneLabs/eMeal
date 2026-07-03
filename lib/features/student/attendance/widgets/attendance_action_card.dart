import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/widgets/preference_group_selector.dart';

/// Card for a single meal's attendance action (Attendance tab).
///
/// Supports five states:
/// 1. **Normal**: preference chips (if enabled) + Present / Skip / Absent
/// 2. **Default Attendance ON**: "Auto-marked Present"; primary = Mark Absent
/// 3. **Vacation**: "Vacation Mode is ON"
/// 4. **Window closed**: locked indicator
/// 5. **Already marked**: confirmation row + "Change" sheet
///
/// When [preferencesEnabled] is true, a compact preference chip row is
/// shown above the action buttons — matching the UX in TodayMealsScreen.
class AttendanceActionCard extends StatefulWidget {
  const AttendanceActionCard({
    super.key,
    required this.meal,
    required this.status,
    required this.onMark,
    this.isWindowOpen = true,
    this.isWindowClosed = false,
    this.isVacationMode = false,
    this.isDefaultAttendance = false,
    this.isLoading = false,
    this.preferencesEnabled = false,
    this.enabledPreferences = const [],
    this.markedPreference,
    this.markedAt,
    this.onRequestCorrection,
    this.onMarkWithSelections,
  });

  /// Module 36 (FR-PG-030/032): used INSTEAD of [onMark] for Present when the
  /// meal carries explicit preference groups — sends the full selection set.
  /// Null or empty groups = legacy flat [onMark] path (FR-PG-021).
  final void Function(
    AttendanceStatus status,
    List<PreferenceSelection> selections,
  )? onMarkWithSelections;

  /// Module 33 (ISSUE-17): opens the correction-request sheet for this meal.
  /// Shown once the window has closed — "I ate, please mark me Present" (or
  /// correcting a wrong record) routes through admin approval, never a silent
  /// edit. Null hides the affordance.
  final VoidCallback? onRequestCorrection;

  final MealModel meal;
  final AttendanceStatus? status;

  /// The preference the student actually submitted (from the backend record).
  /// Rendered under the marked status so the card reflects the stored choice.
  final String? markedPreference;

  /// Submission timestamp from the backend record (local time). Rendered as a
  /// "Submitted at h:mm AM" line on the marked card.
  final DateTime? markedAt;

  /// True when the attendance window has already CLOSED for today (past close
  /// time). Used to show an explicit "Attendance closed" note on a marked meal.
  final bool isWindowClosed;

  /// Called when the student marks attendance with an optional preference.
  final void Function(AttendanceStatus status, {String? preference}) onMark;

  final bool isWindowOpen;
  final bool isVacationMode;
  final bool isDefaultAttendance;
  final bool isLoading;

  /// When true, a compact preference chip row is shown before the action buttons.
  final bool preferencesEnabled;

  /// Admin-configured preference tags (raw strings) — supports custom tags.
  final List<String> enabledPreferences;

  @override
  State<AttendanceActionCard> createState() => _AttendanceActionCardState();
}

class _AttendanceActionCardState extends State<AttendanceActionCard> {
  String? _selectedPreference;

  // Module 36: grouped-selection state (explicit preference groups).
  List<PreferenceSelection> _groupSelections = const [];
  bool _groupSelectionComplete = false;

  bool get _hasPreferenceGroups =>
      widget.meal.preferenceGroups.isNotEmpty &&
      widget.onMarkWithSelections != null;

  bool get _isPending =>
      widget.status == null || widget.status == AttendanceStatus.pending;

  bool get _canMark =>
      widget.isWindowOpen &&
      !widget.isVacationMode &&
      !widget.isLoading &&
      _isPending;

  /// Spec gating: when meal preferences are enabled for this meal, the
  /// Present action stays disabled until the student picks a preference
  /// (Absent / Skip remain enabled — a preference is only needed to consume
  /// the meal). When preferences are off, Present behaves like _canMark.
  bool get _canMarkPresent =>
      _canMark &&
      (_hasPreferenceGroups
          // FR-PG-032: Present unlocks once all required groups are satisfied.
          ? _groupSelectionComplete
          : (!widget.preferencesEnabled ||
              widget.enabledPreferences.isEmpty ||
              _selectedPreference != null));

  void _markWithPreference(AttendanceStatus status) {
    if (_hasPreferenceGroups) {
      // FR-PG-031: Absent/Skip need no selections; Present sends the set.
      widget.onMarkWithSelections!(
        status,
        status == AttendanceStatus.present
            ? _groupSelections
            : const <PreferenceSelection>[],
      );
      return;
    }
    widget.onMark(
      status,
      preference: widget.preferencesEnabled ? _selectedPreference : null,
    );
  }

  /// Display label for a stored preference key (e.g. "veg" -> "Veg"). Custom
  /// admin tag names are shown as-is apart from capitalising the first letter.
  String _prefLabel(String key) {
    final k = key.trim();
    if (k.isEmpty) return k;
    return k[0].toUpperCase() + k.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = MealModel.iconBgColor(widget.meal.order);
    final fgColor = MealModel.iconFgColor(widget.meal.order);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.5)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(AppConstants.space16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.meal.icon, color: fgColor, size: 22),
                ),
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.meal.name,
                        style: AppTypography.titleSmall.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            TimeFormat.window12(
                                widget.meal.attendanceWindow.openTime,
                                widget.meal.attendanceWindow.closeTime),
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _StatusBadge(
                  status: widget.status,
                  isWindowOpen: widget.isWindowOpen,
                  isVacationMode: widget.isVacationMode,
                ),
              ],
            ),
          ),

          // Module 36 (FR-PG-030): grouped selection sections with live price.
          if (_hasPreferenceGroups &&
              _isPending &&
              !widget.isVacationMode &&
              widget.isWindowOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space16, 0, AppConstants.space16, 4),
              child: PreferenceGroupSelector(
                groups: widget.meal.preferenceGroups,
                enabled: !widget.isLoading,
                onChanged: (selections, delta, complete) => setState(() {
                  _groupSelections = selections;
                  _groupSelectionComplete = complete;
                }),
              ),
            ),

          // Preference chip row (shown when enabled + window open + unmarked)
          if (!_hasPreferenceGroups &&
              widget.preferencesEnabled &&
              widget.enabledPreferences.isNotEmpty &&
              _isPending &&
              !widget.isVacationMode &&
              widget.isWindowOpen)
            _PreferenceRow(
              options: widget.enabledPreferences,
              selected: _selectedPreference,
              onSelect: (opt) => setState(() {
                _selectedPreference =
                    _selectedPreference == opt ? null : opt;
              }),
              isDark: isDark,
            ),

          // Action area
          if (!_isPending)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space16,
                0,
                AppConstants.space16,
                AppConstants.space12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MarkedRow(
                    status: widget.status!,
                    isDark: isDark,
                    canChange: widget.isWindowOpen && !widget.isVacationMode,
                    onMark: (s) => _markWithPreference(s),
                  ),
                  // Submitted preference + time, rendered from the backend
                  // attendance record so the marked state is fully reflected.
                  if (widget.status == AttendanceStatus.present &&
                      (widget.markedPreference?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 6),
                    _MarkedMetaLine(
                      icon: Icons.local_dining_rounded,
                      text: 'Preference: '
                          '${_prefLabel(widget.markedPreference!)}',
                      isDark: isDark,
                    ),
                  ],
                  if (widget.markedAt != null) ...[
                    const SizedBox(height: 4),
                    _MarkedMetaLine(
                      icon: Icons.check_rounded,
                      text:
                          'Submitted at ${TimeFormat.tod12(TimeOfDay.fromDateTime(widget.markedAt!))}',
                      isDark: isDark,
                    ),
                  ],
                  // Once the window has closed, the student can no longer change
                  // attendance — show that clearly instead of a silent state.
                  if (widget.isWindowClosed) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.lock_clock_rounded,
                            size: 13,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textTertiary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Attendance closed — you can no longer change this meal.',
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Module 33 (ISSUE-17): the sanctioned post-close path —
                    // a correction request the admin reviews.
                    if (widget.onRequestCorrection != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onRequestCorrection,
                          icon: const Icon(Icons.rule_rounded, size: 15),
                          label: const Text('Request correction'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            )
          else if (widget.isVacationMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space16,
                0,
                AppConstants.space16,
                AppConstants.space12,
              ),
              child: Row(
                children: [
                  const Icon(Icons.beach_access_rounded,
                      size: 14, color: AppColors.vacation),
                  const SizedBox(width: AppConstants.space8),
                  Text(
                    'Attendance paused - vacation mode is ON',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.vacation,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else if (!widget.isWindowOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space16,
                0,
                AppConstants.space16,
                AppConstants.space12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.lock_clock_rounded,
                        size: 14,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textTertiary,
                      ),
                      const SizedBox(width: AppConstants.space8),
                      Text(
                        'Attendance window is closed',
                        style: AppTypography.bodySmall.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  // Module 33 (ISSUE-17): "I ate but the window closed" — the
                  // student raises a claim the admin approves; only then is
                  // Present recorded and billed.
                  if (widget.isWindowClosed &&
                      widget.onRequestCorrection != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: widget.onRequestCorrection,
                        icon: const Icon(Icons.rule_rounded, size: 15),
                        label: const Text('Request correction'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else if (widget.isDefaultAttendance)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space16,
                0,
                AppConstants.space16,
                AppConstants.space16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Auto-marked Present - tap only if changing:',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppConstants.space8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _canMark
                              ? () => _markWithPreference(AttendanceStatus.absent)
                              : null,
                          icon: const Icon(Icons.cancel_outlined,
                              size: 16, color: AppColors.absent),
                          label: const Text('Mark Absent'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.absent,
                            side: BorderSide(
                                color: AppColors.absent.withValues(alpha: 0.4)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            textStyle: AppTypography.labelLarge
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppConstants.space8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _canMark
                              ? () => _markWithPreference(AttendanceStatus.skipped)
                              : null,
                          style: OutlinedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            textStyle: AppTypography.labelLarge
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Skip'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.space16,
                0,
                AppConstants.space16,
                AppConstants.space16,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: _canMarkPresent
                          ? () => _markWithPreference(AttendanceStatus.present)
                          : null,
                      icon: widget.isLoading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Present'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.present,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        textStyle: AppTypography.labelLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.space8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: _canMark
                          ? () => _markWithPreference(AttendanceStatus.skipped)
                          : null,
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        textStyle: AppTypography.labelLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.space8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: _canMark
                          ? () => _markWithPreference(AttendanceStatus.absent)
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.absent,
                        side: BorderSide(
                          color: _canMark
                              ? AppColors.absent.withValues(alpha: 0.5)
                              : AppColors.textTertiary
                                  .withValues(alpha: 0.3),
                        ),
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                        textStyle: AppTypography.labelLarge
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Absent'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Preference chip row

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.options,
    required this.selected,
    required this.onSelect,
    required this.isDark,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelect;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.space16,
        0,
        AppConstants.space16,
        AppConstants.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Meal preference (required)',
            style: AppTypography.labelSmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppConstants.space8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isSelected = selected == opt;
              final disp = MealPreferenceOption.display(opt);
              return GestureDetector(
                onTap: () => onSelect(opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : isDark
                            ? AppColors.surfaceVariantDark
                            : AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : isDark
                              ? AppColors.borderDark.withValues(alpha: 0.5)
                              : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(disp.emoji, style: const TextStyle(fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(
                        disp.label,
                        style: AppTypography.labelSmall.copyWith(
                          color: isSelected
                              ? Colors.white
                              : isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// Marked row

class _MarkedRow extends StatelessWidget {
  const _MarkedRow({
    required this.status,
    required this.isDark,
    required this.canChange,
    required this.onMark,
  });

  final AttendanceStatus status;
  final bool isDark;
  final bool canChange;
  final void Function(AttendanceStatus) onMark;

  (IconData, String, Color) get _props {
    switch (status) {
      case AttendanceStatus.present:
        return (Icons.check_circle_rounded, 'Marked Present', AppColors.present);
      case AttendanceStatus.absent:
        return (Icons.cancel_rounded, 'Marked Absent', AppColors.absent);
      case AttendanceStatus.skipped:
        return (Icons.remove_circle_rounded, 'Skipped', AppColors.skipped);
      case AttendanceStatus.onVacation:
        return (Icons.beach_access_rounded, 'On Vacation', AppColors.vacation);
      case AttendanceStatus.pending:
        return (Icons.pending_rounded, 'Pending', AppColors.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _props;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppConstants.space8),
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (canChange) ...[
          const Spacer(),
          TextButton(
            onPressed: () => _showChangeSheet(context),
            style: TextButton.styleFrom(
              foregroundColor: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.space8,
                vertical: 4,
              ),
            ),
            child: Text(
              'Change',
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showChangeSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(AppConstants.space24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.bottomSheetRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Change attendance',
              style: AppTypography.titleMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.space16),
            _sheetOption(context, Icons.check_circle_rounded, 'Mark Present',
                AppColors.present, AttendanceStatus.present, isDark),
            const SizedBox(height: AppConstants.space8),
            _sheetOption(context, Icons.remove_circle_rounded, 'Skip',
                AppColors.skipped, AttendanceStatus.skipped, isDark),
            const SizedBox(height: AppConstants.space8),
            _sheetOption(context, Icons.cancel_rounded, 'Mark Absent',
                AppColors.absent, AttendanceStatus.absent, isDark),
            const SizedBox(height: AppConstants.space8),
          ],
        ),
      ),
    );
  }

  Widget _sheetOption(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
    AttendanceStatus s,
    bool isDark,
  ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onMark(s);
      },
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.space16,
          vertical: AppConstants.space12,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppConstants.space12),
            Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Status badge

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.isWindowOpen,
    required this.isVacationMode,
  });

  final AttendanceStatus? status;
  final bool isWindowOpen;
  final bool isVacationMode;

  @override
  Widget build(BuildContext context) {
    if (isVacationMode) return _chip('Vacation', AppColors.vacation);
    if (status == null || status == AttendanceStatus.pending) {
      return _chip(
        isWindowOpen ? 'Open' : 'Closed',
        isWindowOpen ? AppColors.secondary : AppColors.textTertiary,
      );
    }
    switch (status!) {
      case AttendanceStatus.present:
        return _chip('Present', AppColors.present);
      case AttendanceStatus.absent:
        return _chip('Absent', AppColors.absent);
      case AttendanceStatus.skipped:
        return _chip('Skipped', AppColors.skipped);
      case AttendanceStatus.onVacation:
        return _chip('Vacation', AppColors.vacation);
      case AttendanceStatus.pending:
        return _chip('Pending', AppColors.warning);
    }
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

// Marked meta line (preference / submitted time)

class _MarkedMetaLine extends StatelessWidget {
  const _MarkedMetaLine({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  final IconData icon;
  final String text;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

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
  });

  final MealModel meal;
  final AttendanceStatus? status;

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
      (!widget.preferencesEnabled ||
          widget.enabledPreferences.isEmpty ||
          _selectedPreference != null);

  void _markWithPreference(AttendanceStatus status) {
    widget.onMark(
      status,
      preference: widget.preferencesEnabled ? _selectedPreference : null,
    );
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
                            '${widget.meal.attendanceWindow.openTime}'
                            ' - ${widget.meal.attendanceWindow.closeTime}',
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

          // Preference chip row (shown when enabled + window open + unmarked)
          if (widget.preferencesEnabled &&
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
              child: Row(
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

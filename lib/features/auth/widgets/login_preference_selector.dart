import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Login Preference selector (SRS Module 01, Part 3 business rule):
/// "Login Preference can be changed later from Profile settings after
/// verification."
///
/// Two chips — Email / Mobile — that mirror the signup selector. The control
/// is enabled only once the email is verified, and the Mobile option
/// additionally requires a mobile number on file (matching the backend guard
/// on `PATCH /users/me`). Helper copy explains a disabled state instead of
/// hiding it.
class LoginPreferenceSelector extends StatelessWidget {
  const LoginPreferenceSelector({
    super.key,
    required this.value,
    required this.emailVerified,
    required this.hasPhone,
    required this.isDark,
    required this.onChanged,
  });

  /// Current preference — 'email' or 'mobile'.
  final String value;

  /// SRS gate: the preference is changeable only after email verification.
  final bool emailVerified;

  /// Mobile option requires a mobile number on file.
  final bool hasPhone;

  final bool isDark;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final labelColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Login Preference',
          style: AppTypography.bodySmall.copyWith(
            color: labelColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.space8),
        Row(
          children: [
            _prefChip(
              label: 'Email',
              icon: Icons.email_rounded,
              selected: value == 'email',
              enabled: emailVerified,
              onTap: () => onChanged('email'),
            ),
            const SizedBox(width: AppConstants.space8),
            _prefChip(
              label: 'Mobile',
              icon: Icons.phone_rounded,
              selected: value == 'mobile',
              enabled: emailVerified && hasPhone,
              onTap: () => onChanged('mobile'),
            ),
          ],
        ),
        if (!emailVerified) ...[
          const SizedBox(height: AppConstants.space8),
          Text(
            'Verify your email to change your login preference.',
            style: AppTypography.bodySmall.copyWith(color: labelColor),
          ),
        ] else if (!hasPhone) ...[
          const SizedBox(height: AppConstants.space8),
          Text(
            'Add a mobile number to enable Mobile login.',
            style: AppTypography.bodySmall.copyWith(color: labelColor),
          ),
        ],
      ],
    );
  }

  Widget _prefChip({
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final baseColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final color = selected ? AppColors.primary : baseColor;
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.08)
                  : (isDark
                      ? AppColors.surfaceVariantDark.withValues(alpha: 0.5)
                      : AppColors.surfaceVariant),
              borderRadius: BorderRadius.circular(AppConstants.inputRadius),
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : (isDark ? AppColors.borderDark : AppColors.border),
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

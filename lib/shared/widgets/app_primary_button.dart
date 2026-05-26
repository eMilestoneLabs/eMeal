import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Visual variant for [AppPrimaryButton].
enum _ButtonVariant { filled, outlined, ghost }

/// The primary button component for the MealAttend design system.
///
/// Three visual variants available via named constructors:
/// - `AppPrimaryButton(...)` — filled / solid (default)
/// - `AppPrimaryButton.outlined(...)` — border with transparent fill
/// - `AppPrimaryButton.ghost(...)` — no border, subtle text-only
class AppPrimaryButton extends StatelessWidget {
  /// Filled / primary variant.
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = true,
    this.height = 52.0,
    this.borderRadius,
  }) : _variant = _ButtonVariant.filled;

  /// Outlined / secondary variant.
  const AppPrimaryButton.outlined({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = true,
    this.height = 52.0,
    this.borderRadius,
  }) : _variant = _ButtonVariant.outlined;

  /// Ghost / tertiary variant — no border, text + optional icon only.
  const AppPrimaryButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = true,
    this.height = 48.0,
    this.borderRadius,
  }) : _variant = _ButtonVariant.ghost;

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool isFullWidth;
  final double height;
  final double? borderRadius;
  final _ButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? AppConstants.buttonRadius;
    final disabled = onPressed == null && !isLoading;

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: height,
      child: switch (_variant) {
        _ButtonVariant.filled => _FilledBtn(
            label: label,
            onPressed: isLoading ? null : onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            isLoading: isLoading,
            disabled: disabled,
            radius: radius,
          ),
        _ButtonVariant.outlined => _OutlinedBtn(
            label: label,
            onPressed: isLoading ? null : onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            isLoading: isLoading,
            isDark: isDark,
            disabled: disabled,
            radius: radius,
          ),
        _ButtonVariant.ghost => _GhostBtn(
            label: label,
            onPressed: isLoading ? null : onPressed,
            icon: icon,
            trailingIcon: trailingIcon,
            isLoading: isLoading,
            disabled: disabled,
            radius: radius,
          ),
      },
    );
  }
}

// ── Filled ────────────────────────────────────────────────────────────────────

class _FilledBtn extends StatelessWidget {
  const _FilledBtn({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    required this.disabled,
    required this.radius,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool disabled;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _handleTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: disabled
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
        disabledForegroundColor: AppColors.onPrimary.withValues(alpha: 0.6),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.zero,
      ),
      child: _Content(
        label: label,
        icon: icon,
        trailingIcon: trailingIcon,
        isLoading: isLoading,
        color: AppColors.onPrimary,
      ),
    );
  }

  VoidCallback? get _handleTap {
    if (isLoading || disabled || onPressed == null) return null;
    return () {
      HapticFeedback.lightImpact();
      onPressed!();
    };
  }
}

// ── Outlined ──────────────────────────────────────────────────────────────────

class _OutlinedBtn extends StatelessWidget {
  const _OutlinedBtn({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    required this.isDark,
    required this.disabled,
    required this.radius,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool isDark;
  final bool disabled;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: _handleTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: disabled
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.primary,
        side: BorderSide(
          color: disabled
              ? (isDark ? AppColors.borderDark : AppColors.border)
                  .withValues(alpha: 0.4)
              : (isDark ? AppColors.borderDark : AppColors.border),
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.zero,
      ),
      child: _Content(
        label: label,
        icon: icon,
        trailingIcon: trailingIcon,
        isLoading: isLoading,
        color: disabled
            ? AppColors.primary.withValues(alpha: 0.4)
            : AppColors.primary,
      ),
    );
  }

  VoidCallback? get _handleTap {
    if (isLoading || disabled || onPressed == null) return null;
    return () {
      HapticFeedback.mediumImpact();
      onPressed!();
    };
  }
}

// ── Ghost ─────────────────────────────────────────────────────────────────────

class _GhostBtn extends StatelessWidget {
  const _GhostBtn({
    required this.label,
    required this.onPressed,
    required this.isLoading,
    required this.disabled,
    required this.radius,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool disabled;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? AppColors.primary.withValues(alpha: 0.4)
        : AppColors.primary;

    return TextButton(
      onPressed: _handleTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.zero,
      ),
      child: _Content(
        label: label,
        icon: icon,
        trailingIcon: trailingIcon,
        isLoading: isLoading,
        color: color,
      ),
    );
  }

  VoidCallback? get _handleTap {
    if (isLoading || disabled || onPressed == null) return null;
    return () {
      HapticFeedback.selectionClick();
      onPressed!();
    };
  }
}

// ── Internal content widget ────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  const _Content({
    required this.label,
    required this.color,
    required this.isLoading,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final Color color;
  final bool isLoading;
  final IconData? icon;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
        ],
        Text(label, style: AppTypography.labelLarge.copyWith(color: color)),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(trailingIcon, size: 18, color: color),
        ],
      ],
    );
  }
}

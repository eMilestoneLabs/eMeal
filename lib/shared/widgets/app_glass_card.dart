import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';

/// A glassmorphism card that can serve as a premium surface.
///
/// Uses [BackdropFilter] with a blur to create a frosted-glass effect.
/// Falls back gracefully to a semi-transparent surface when glass is disabled.
///
/// ```dart
/// AppGlassCard(
///   child: Text('Hello'),
/// )
/// ```
class AppGlassCard extends StatelessWidget {
  const AppGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.blur = 12.0,
    this.opacity = 0.8,
    this.backgroundColor,
    this.borderColor,
    this.onTap,
    this.elevation = 0,
    this.glassEnabled = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final double blur;

  /// Opacity of the background fill (0–1). Lower = more transparent.
  final double opacity;
  final Color? backgroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final double elevation;

  /// When false, renders as a regular card with no blur (perf-friendly).
  final bool glassEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? AppConstants.cardRadius;

    final bg = backgroundColor ??
        (isDark
            ? AppColors.surfaceDark.withValues(alpha: opacity)
            : AppColors.surface.withValues(alpha: opacity));

    final border = borderColor ??
        (isDark ? AppColors.glassBorder : AppColors.border.withValues(alpha: 0.6));

    Widget card = Container(
      padding: padding ?? const EdgeInsets.all(AppConstants.space16),
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: 1),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: elevation * 4,
                  offset: Offset(0, elevation),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (glassEnabled) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: card,
        ),
      );
    }

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}

/// A standard (non-glass) card that follows the design system surface rules.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.onTap,
    this.elevation = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final VoidCallback? onTap;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? AppConstants.cardRadius;

    final content = Container(
      padding: padding ?? const EdgeInsets.all(AppConstants.space16),
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.border,
          width: 1,
        ),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: elevation * 4,
                  offset: Offset(0, elevation),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: content,
        ),
      );
    }

    return content;
  }
}

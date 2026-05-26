import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';

/// Screen-size categories used throughout the app.
enum ScreenSize { mobile, tablet, desktop }

/// Responsive layout helpers for the MealAttend design system.
///
/// Usage:
/// ```dart
/// if (context.isMobile) { ... }
///
/// final cols = context.responsive(mobile: 1, tablet: 2, desktop: 3);
/// ```
extension ResponsiveExtension on BuildContext {
  // ── Screen size detection ──────────────────────────────────────────────────
  // Raw width/height live in ThemeContextExt (context_ext.dart).
  // This extension adds breakpoint-based classification on top.

  bool get isMobile =>
      MediaQuery.sizeOf(this).width < AppConstants.mobileBreakpoint;
  bool get isTablet {
    final w = MediaQuery.sizeOf(this).width;
    return w >= AppConstants.mobileBreakpoint &&
        w < AppConstants.tabletBreakpoint;
  }

  bool get isDesktop =>
      MediaQuery.sizeOf(this).width >= AppConstants.tabletBreakpoint;

  ScreenSize get screenSize {
    if (isMobile) return ScreenSize.mobile;
    if (isTablet) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }

  // ── Responsive value picker ────────────────────────────────────────────────

  /// Returns the appropriate value for the current screen size.
  ///
  /// [tablet] and [desktop] fall back to the next smaller value if not
  /// provided, so you only need to specify what changes.
  T responsive<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop) return desktop ?? tablet ?? mobile;
    if (isTablet) return tablet ?? mobile;
    return mobile;
  }

  // ── Horizontal page padding ────────────────────────────────────────────────

  /// Returns edge-to-edge horizontal padding appropriate for the screen size.
  EdgeInsets get pagePadding => EdgeInsets.symmetric(
        horizontal: responsive(
          mobile: AppConstants.pagePaddingH,
          tablet: 40.0,
          desktop: 64.0,
        ),
        vertical: AppConstants.pagePaddingV,
      );

  /// Horizontal padding only.
  double get pageHorizontalPadding => responsive(
        mobile: AppConstants.pagePaddingH,
        tablet: 40.0,
        desktop: 64.0,
      );

  // ── Grid columns ──────────────────────────────────────────────────────────

  /// Analytics / card grid columns.
  int get analyticsColumnCount => responsive(
        mobile: 2,
        tablet: 3,
        desktop: 4,
      );

  /// List / content grid columns.
  int get contentColumnCount => responsive(
        mobile: 1,
        tablet: 2,
        desktop: 3,
      );
}

/// Static helpers for use outside of widget build methods.
abstract final class ResponsiveHelper {
  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppConstants.mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= AppConstants.mobileBreakpoint &&
        w < AppConstants.tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppConstants.tabletBreakpoint;

  static ScreenSize screenSize(BuildContext context) {
    if (isMobile(context)) return ScreenSize.mobile;
    if (isTablet(context)) return ScreenSize.tablet;
    return ScreenSize.desktop;
  }


  /// Clamps a column count to a sensible range for the current screen size.
  ///
  /// Useful for responsive grids:
  /// ```dart
  /// final cols = ResponsiveHelper.clampColumns(context, mobile: 1, tablet: 2, desktop: 3);
  /// ```
  static int clampColumns(
    BuildContext context, {
    required int mobile,
    int? tablet,
    int? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }
}

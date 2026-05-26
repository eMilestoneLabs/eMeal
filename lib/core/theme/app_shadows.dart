import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';

/// Semantic shadow / elevation definitions for the MealAttend design system.
///
/// All shadows use `AppColors` primitives so they respond to theme changes.
/// Use these instead of ad-hoc `BoxShadow` literals so that elevation cues
/// are consistent across the entire UI.
///
/// ## Usage
///
/// ```dart
/// Container(
///   decoration: BoxDecoration(
///     boxShadow: AppShadows.card,
///   ),
/// )
/// ```
///
/// ## Glassmorphism-ready
///
/// The [glass] shadow is intentionally soft to complement frosted-glass card
/// overlays.  Pair it with a semi-transparent background and a subtle border.
abstract final class AppShadows {
  // ── Light theme shadows ────────────────────────────────────────────────────

  /// No elevation — flat surface, border-only separation.
  static const List<BoxShadow> none = [];

  /// Subtle lift — standard card, input field focus ring shadow.
  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0A000000), // black 4%
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
    BoxShadow(
      color: Color(0x06000000), // black 2%
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// Medium elevation — floating action buttons, bottom sheets peek.
  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x14000000), // black 8%
      blurRadius: 20,
      offset: Offset(0, 4),
    ),
    BoxShadow(
      color: Color(0x08000000), // black 3%
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Strong elevation — modals, dialogs, pop-up menus.
  static const List<BoxShadow> modal = [
    BoxShadow(
      color: Color(0x1A000000), // black 10%
      blurRadius: 32,
      offset: Offset(0, 8),
    ),
    BoxShadow(
      color: Color(0x0A000000), // black 4%
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  /// Primary-tinted glow — highlight on active / focused premium buttons.
  static List<BoxShadow> primaryGlow = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.30),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// Soft halo for glassmorphism cards — pairs with a backdrop blur.
  static const List<BoxShadow> glass = [
    BoxShadow(
      color: Color(0x0CFFFFFF), // white 5%
      blurRadius: 1,
      offset: Offset(0, 1),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x14000000), // black 8%
      blurRadius: 24,
      offset: Offset(0, 6),
    ),
  ];

  // ── Dark theme shadows ─────────────────────────────────────────────────────
  // Dark surfaces rely on lighter blurs — deep blacks wash out in dark mode.

  /// Subtle lift in dark theme.
  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x1A000000), // black 10%
      blurRadius: 12,
      offset: Offset(0, 3),
    ),
  ];

  /// Medium elevation in dark theme.
  static const List<BoxShadow> elevatedDark = [
    BoxShadow(
      color: Color(0x28000000), // black 16%
      blurRadius: 24,
      offset: Offset(0, 6),
    ),
  ];

  /// Strong elevation in dark theme — modals, dialogs.
  static const List<BoxShadow> modalDark = [
    BoxShadow(
      color: Color(0x33000000), // black 20%
      blurRadius: 40,
      offset: Offset(0, 10),
    ),
  ];

  /// Primary-tinted glow in dark theme.
  static List<BoxShadow> primaryGlowDark = [
    BoxShadow(
      color: AppColors.primaryLight.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];
}

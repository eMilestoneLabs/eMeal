import 'package:flutter/material.dart';

/// Central colour palette for the MealAttend design system.
///
/// All colour references across the codebase must go through this class —
/// never hard-code hex values in widget files.
abstract final class AppColors {
  // ── Brand ──────────────────────────────────────────────────────────────────
  /// Deep indigo — primary action colour (Linear-inspired).
  static const Color primary = Color(0xFF4F46E5);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF3730A3);
  static const Color primaryContainer = Color(0xFFEEF2FF);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF3730A3);

  /// Rich violet — used as the end-stop of premium gradient surfaces
  /// (greeting cards, hero banners) to give a vivid indigo→violet look.
  static const Color violet = Color(0xFF7C3AED);

  /// Emerald — secondary / meal-status accent.
  static const Color secondary = Color(0xFF059669);
  static const Color secondaryLight = Color(0xFF34D399);
  static const Color secondaryDark = Color(0xFF065F46);
  static const Color secondaryContainer = Color(0xFFD1FAE5);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF065F46);

  /// Sky blue — info / good states.
  static const Color info = Color(0xFF3B82F6);

  /// Amber — warning / pending states.
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color onWarningContainer = Color(0xFF92400E);

  /// Rose — error / absent states.
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color onErrorContainer = Color(0xFF991B1B);

  // ── Surfaces ───────────────────────────────────────────────────────────────
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // ── Borders ────────────────────────────────────────────────────────────────
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);
  static const Color divider = Color(0xFFF1F5F9);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textDisabled = Color(0xFFCBD5E1);
  static const Color textInverse = Color(0xFFFFFFFF);

  // ── Dark theme surfaces ────────────────────────────────────────────────────
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color surfaceVariantDark = Color(0xFF334155);
  static const Color surfaceElevatedDark = Color(0xFF253347); // slightly above surfaceDark
  static const Color borderDark = Color(0xFF334155);
  static const Color borderStrongDark = Color(0xFF475569);
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color textTertiaryDark = Color(0xFF475569);

  // ── Glassmorphism ──────────────────────────────────────────────────────────
  static const Color glassWhite = Color(0xCCFFFFFF);       // 80% white
  static const Color glassBorder = Color(0x33FFFFFF);      // 20% white
  static const Color glassDark = Color(0xCC1E293B);        // 80% dark surface
  static const Color glassBorderDark = Color(0x22FFFFFF);  // 13% white

  // ── Gradient stops ─────────────────────────────────────────────────────────
  /// Indigo-violet for primary gradient end
  static const Color gradientEnd = Color(0xFF6366F1);
  /// Deep purple for accent gradients
  static const Color gradientPurple = Color(0xFF7C3AED);
  /// Violet for splash/hero gradients
  static const Color gradientViolet = Color(0xFF8B5CF6);

  // ── Glow / ambient ────────────────────────────────────────────────────────
  /// Primary indigo glow — used for logo shadows, hero glows
  static const Color glowPrimary = Color(0x664F46E5);    // 40% primary
  /// Soft secondary glow
  static const Color glowSecondary = Color(0x4D059669);  // 30% secondary
  /// Warm purple glow for event screens
  static const Color glowPurple = Color(0x558B5CF6);     // 33% violet

  // ── Splash background ─────────────────────────────────────────────────────
  /// Dark splash: deep navy-black base
  static const Color splashDark = Color(0xFF080C18);
  /// Dark splash: second layer (slate)
  static const Color splashDarkMid = Color(0xFF0D1425);
  /// Light splash: soft pearl-blue base
  static const Color splashLight = Color(0xFFF5F7FF);
  /// Light splash: soft lavender mid
  static const Color splashLightMid = Color(0xFFEEF2FF);

  // ── Status ─────────────────────────────────────────────────────────────────
  static const Color present = Color(0xFF059669);
  static const Color absent = Color(0xFFEF4444);
  static const Color skipped = Color(0xFFF59E0B);
  static const Color vacation = Color(0xFF8B5CF6);
}

/// Semantic spacing constants for the MealAttend design system.
///
/// All spacing values derive from a 4px base grid. Use these constants
/// instead of raw numeric literals to ensure visual consistency and make
/// future grid changes a single-file update.
///
/// ## Usage
///
/// ```dart
/// Padding(
///   padding: const EdgeInsets.all(AppSpacing.md),
///   child: ...,
/// )
/// SizedBox(height: AppSpacing.lg)
/// ```
abstract final class AppSpacing {
  // ── Base grid ──────────────────────────────────────────────────────────────

  /// 2px — hairline gap, e.g. between badge icon and text.
  static const double xxs = 2;

  /// 4px — tight spacing within a single component.
  static const double xs = 4;

  /// 8px — intra-component spacing (icon ↔ label, chip padding).
  static const double sm = 8;

  /// 12px — compact vertical gaps between related items.
  static const double md = 12;

  /// 16px — standard content padding / section gap.
  static const double lg = 16;

  /// 20px — page horizontal padding (matches [pagePaddingH]).
  static const double xl = 20;

  /// 24px — section-to-section gap.
  static const double xxl = 24;

  /// 32px — large section separation.
  static const double xxxl = 32;

  /// 48px — hero / splash spacing.
  static const double huge = 48;

  // ── Semantic aliases ───────────────────────────────────────────────────────

  /// Standard horizontal padding on every scrollable page.
  static const double pagePaddingH = xl;

  /// Bottom-safe area minimum padding (before [MediaQuery.padding.bottom]).
  static const double pageBottomPadding = xxl;

  /// Inner card padding (symmetric).
  static const double cardPaddingH = lg;
  static const double cardPaddingV = md;

  /// Gap between consecutive list tiles.
  static const double tileSeparator = sm;

  /// Gap between consecutive section cards.
  static const double sectionGap = xxl;

  /// Radius for standard cards.
  static const double cardRadius = 16;

  /// Radius for chips and small badges.
  static const double chipRadius = 8;

  /// Radius for dialogs and bottom sheets.
  static const double sheetRadius = 24;

  /// Radius for text inputs.
  static const double inputRadius = 12;

  /// Radius for premium buttons.
  static const double buttonRadius = 12;

  // ── Icon sizes ─────────────────────────────────────────────────────────────

  /// Compact icon (e.g. leading in a ListTile subtitle).
  static const double iconSm = 16;

  /// Standard icon size.
  static const double iconMd = 20;

  /// Large icon (e.g. section headers, empty-state illustrations).
  static const double iconLg = 24;

  /// Extra-large / feature icon.
  static const double iconXl = 32;

  /// Hero / splash icon.
  static const double iconHero = 48;
}

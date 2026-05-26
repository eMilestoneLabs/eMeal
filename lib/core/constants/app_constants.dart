/// App-wide constants for the MealAttend platform.
///
/// Group all magic numbers, strings, and configuration values here so they
/// are easy to find, test, and change without hunting through widget files.
abstract final class AppConstants {
  // ── App meta ───────────────────────────────────────────────────────────────
  static const String appName = 'MealAttend';
  static const String appTagline = 'Smart Meal & Attendance Management';
  static const String packageName = 'smart_meal_management';

  // ── API / Backend (future) ─────────────────────────────────────────────────
  static const String apiBaseUrlDev = 'http://localhost:3000/api/v1';
  static const String apiBaseUrlProd = 'https://api.emilestone.com/v1';
  static const int apiTimeoutSeconds = 30;

  // ── Responsive breakpoints ─────────────────────────────────────────────────
  /// Below this width → mobile layout.
  static const double mobileBreakpoint = 600;

  /// Below this width → tablet layout (above = desktop).
  static const double tabletBreakpoint = 1024;

  // ── Layout ─────────────────────────────────────────────────────────────────
  static const double pagePaddingH = 20.0;
  static const double pagePaddingV = 24.0;
  static const double cardRadius = 16.0;
  static const double buttonHeight = 56.0;
  static const double buttonRadius = 12.0;
  static const double inputRadius = 12.0;
  static const double chipRadius = 8.0;
  static const double dialogRadius = 20.0;
  static const double bottomSheetRadius = 24.0;

  // ── Spacing scale (4-pt grid) ──────────────────────────────────────────────
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // ── Image constraints ──────────────────────────────────────────────────────
  /// Max file size for admin-uploaded meal images (bytes).
  static const int maxMealImageBytes = 200 * 1024; // 200 KB

  // ── Attendance window ──────────────────────────────────────────────────────
  /// Minutes before a meal window closes that reminders fire.
  static const int reminderLeadMinutes1 = 60;
  static const int reminderLeadMinutes2 = 30;

  // ── Pagination ─────────────────────────────────────────────────────────────
  static const int defaultPageSize = 20;
  static const int exportPageSize = 500;

  // ── Animation durations ────────────────────────────────────────────────────
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
}

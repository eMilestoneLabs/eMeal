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
  /// Max file size for the single admin-uploaded meal image (bytes).
  /// One photo per meal, replaced on each upload (no historical copies).
  static const int maxMealImageBytes = 100 * 1024; // 100 KB

  /// Maximum number of images a meal may carry. Exactly one.
  static const int maxMealImages = 1;

  /// SRS Module 03 MMT-001: Master Meal Template cap per group. Mirrors the
  /// server default (MEALS_MAX_PER_GROUP) — the server stays authoritative;
  /// this only powers the friendly pre-save gate on Add Meal.
  static const int maxMasterMealsPerGroup = 10;

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

  // ── SWR cache ──────────────────────────────────────────────────────────────
  /// Max age for the staff self-attendance instant paint
  /// (`staff_today:{org}:{group}:{user}`). Matches the 12h the other SWR
  /// surfaces use; the network ALWAYS overwrites, so this only bounds how old
  /// a first paint may be before the screen falls back to its loader.
  static const Duration staffTodayCacheMaxAge = Duration(hours: 12);

  // ── Navigation ─────────────────────────────────────────────────────────────
  /// Live-Test-16 ISSUE-2: on a role shell's HOME tab there is nothing left to
  /// pop, so Android back would close the app. A second back press inside this
  /// window confirms the exit; the first one only shows the hint. Configurable
  /// here rather than inline so the confirm window is tuned in one place.
  static const Duration backExitConfirmWindow = Duration(seconds: 2);
}

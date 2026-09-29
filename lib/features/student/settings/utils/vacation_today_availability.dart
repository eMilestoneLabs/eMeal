import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/utils/attendance_window.dart';

/// Live-Test-16 ISSUE-2 — which of TODAY's meals a member may still start a
/// vacation from.
///
/// A meal is OFF-LIMITS once its window has passed (server-clock gate) or
/// once the member already has a record for it (present / absent / skipped
/// — the meal is decided and billed as such). Vacation can only cover
/// UPCOMING meals, never history. The server applies the same rule as a
/// secondary guard (VACATION_MEAL_ALREADY_TAKEN).
///
/// PURE — takes data the caller already holds; no I/O.
class VacationTodayAvailability {
  const VacationTodayAvailability({
    required this.blockedSlotKeys,
    required this.upcomingSlotKeys,
    this.orgToday,
  });

  /// Today's slot keys that can no longer be covered.
  final Set<String> blockedSlotKeys;

  /// Today's slot keys a vacation may still start from.
  final Set<String> upcomingSlotKeys;

  /// Org-timezone business day from the server payload (null = unknown →
  /// the caller falls back to the device day, as before).
  final DateTime? orgToday;

  /// "Whole day" today is only meaningful while nothing today is decided.
  bool get wholeDayTodayAllowed => blockedSlotKeys.isEmpty;

  /// False when every meal today is past or taken → vacation starts tomorrow.
  bool get hasUpcomingToday =>
      upcomingSlotKeys.isNotEmpty ||
      (blockedSlotKeys.isEmpty && upcomingSlotKeys.isEmpty);

  static const _taken = {
    AttendanceStatus.present,
    AttendanceStatus.absent,
    AttendanceStatus.skipped,
  };

  static VacationTodayAvailability compute({
    required List<MealModel> todayMeals,
    required List<AttendanceModel> myTodayRecords,
    DateTime? fetchedAt,
  }) {
    final takenMealIds = {
      for (final r in myTodayRecords)
        if (_taken.contains(r.status)) r.mealId,
    };
    final blocked = <String>{};
    final upcoming = <String>{};
    DateTime? orgToday;
    for (final m in todayMeals) {
      final od = m.orgDate;
      if (orgToday == null && od != null && od.length >= 10) {
        orgToday = DateTime.tryParse(od.substring(0, 10));
      }
      final key = m.slotKey;
      if (takenMealIds.contains(m.id) ||
          AttendanceWindow.isPast(m, fetchedAt: fetchedAt)) {
        blocked.add(key);
      } else {
        upcoming.add(key);
      }
    }
    // A slot shared by several meals is blocked if ANY of them is decided.
    upcoming.removeAll(blocked);
    return VacationTodayAvailability(
      blockedSlotKeys: blocked,
      upcomingSlotKeys: upcoming,
      orgToday: orgToday,
    );
  }
}

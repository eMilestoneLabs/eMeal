import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';

/// planner_dates.dart — Live-Test-15 ISSUE-1.
///
/// SINGLE SOURCE OF TRUTH for "which calendar date does this planner cell
/// belong to?". Save and publish both resolve dates through here, so the two
/// can never disagree about what they are writing.
///
/// WEEKLY mode
///   The seven cells are the current ISO week: `Monday + dayIndex`. Unchanged.
///
/// DAY-WISE mode
///   The planner shows exactly TODAY and TOMORROW — two consecutive CALENDAR
///   dates. Routing them through `Monday + dayIndex` was wrong on a **Sunday**:
///   tomorrow is Monday, and Monday is index 0 of the CURRENT week, so
///   "Tomorrow" was written SIX DAYS IN THE PAST. That silently overwrote a
///   past day and gave the Day-Wise carry-forward baseline a bogus ordering.
///
///   Day-Wise therefore resolves each day to its ACTUAL date, so Sunday →
///   Monday correctly crosses into the next ISO week. The planner is defined by
///   consecutive calendar dates; the `MealSchedule.weekStart` row is storage
///   organisation and must never redefine what "Tomorrow" means.
///
/// The result is a MAP, not a list, so the day set is authoritative: a day
/// absent from it is not part of this plan. That is what makes a Day-Wise save
/// ship exactly its two cells instead of all seven weekdays the draft model
/// happens to hold.
Map<DayOfWeek, DateTime> plannerDates({
  required bool dayWise,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  if (dayWise) {
    final tomorrow = today.add(const Duration(days: 1));
    return <DayOfWeek, DateTime>{
      DayOfWeek.fromWeekday(today.weekday): today,
      DayOfWeek.fromWeekday(tomorrow.weekday): tomorrow,
    };
  }
  final monday = today.subtract(Duration(days: today.weekday - 1));
  return <DayOfWeek, DateTime>{
    for (final d in DayOfWeek.values) d: monday.add(Duration(days: d.index)),
  };
}

/// `YYYY-MM-DD` — the wire format every schedule endpoint expects.
String formatPlannerDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/utils/planner_dates.dart';

/// Live-Test-15 ISSUE-1 — DAY-WISE IS DEFINED BY CALENDAR DATES.
///
/// "Today + Tomorrow" are two consecutive CALENDAR dates. The
/// `MealSchedule.weekStart` row is storage organisation and must never
/// redefine what "Tomorrow" means. The Sunday case is the one that used to be
/// wrong: tomorrow is Monday, Monday is index 0 of the CURRENT ISO week, so
/// `Monday + dayIndex` wrote "Tomorrow" SIX DAYS IN THE PAST.
void main() {
  DateTime d(String s) => DateTime.parse('$s 12:00:00');
  String iso(DateTime x) => formatPlannerDate(x);

  group('plannerDates — DAY-WISE', () {
    test('Thursday → Today=Thu, Tomorrow=Fri (same ISO week)', () {
      final m = plannerDates(dayWise: true, now: d('2026-08-06')); // Thursday
      expect(m.length, 2);
      expect(iso(m[DayOfWeek.thursday]!), '2026-08-06');
      expect(iso(m[DayOfWeek.friday]!), '2026-08-07');
    });

    test('SUNDAY → Tomorrow is NEXT week\'s Monday, never the past one', () {
      final m = plannerDates(dayWise: true, now: d('2026-08-09')); // Sunday
      expect(m.length, 2);
      expect(iso(m[DayOfWeek.sunday]!), '2026-08-09');
      // The regression: this used to resolve to 2026-08-03 (6 days earlier).
      expect(iso(m[DayOfWeek.monday]!), '2026-08-10');
      expect(m[DayOfWeek.monday]!.isAfter(m[DayOfWeek.sunday]!), isTrue);
    });

    test('Tomorrow is ALWAYS exactly one day after Today, every weekday', () {
      for (var i = 0; i < 7; i++) {
        final now = d('2026-08-03').add(Duration(days: i));
        final m = plannerDates(dayWise: true, now: now);
        final dates = m.values.toList()..sort();
        expect(dates.length, 2);
        expect(dates[1].difference(dates[0]).inDays, 1,
            reason: 'failed for ${iso(now)}');
      }
    });

    test('exposes exactly two days, so a Day-Wise save ships two cells', () {
      final m = plannerDates(dayWise: true, now: d('2026-08-06'));
      expect(m.keys.length, 2);
      expect(m[DayOfWeek.wednesday], isNull);
    });
  });

  group('plannerDates — WEEKLY (must stay byte-identical)', () {
    test('all 7 weekdays map to the CURRENT ISO week, Monday-anchored', () {
      final m = plannerDates(dayWise: false, now: d('2026-08-06')); // Thursday
      expect(m.length, 7);
      expect(iso(m[DayOfWeek.monday]!), '2026-08-03');
      expect(iso(m[DayOfWeek.sunday]!), '2026-08-09');
    });

    test('Sunday still anchors to the SAME week (weekly is week-based)', () {
      final m = plannerDates(dayWise: false, now: d('2026-08-09')); // Sunday
      expect(iso(m[DayOfWeek.monday]!), '2026-08-03');
      expect(iso(m[DayOfWeek.sunday]!), '2026-08-09');
    });
  });
}

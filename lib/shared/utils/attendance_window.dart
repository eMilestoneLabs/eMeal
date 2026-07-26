import 'package:flutter/material.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

/// Live-Test-14 ISSUE-001 — the ONE attendance-window gate.
///
/// ## Why this exists
/// The member attendance card has always gated its Present / Absent buttons on
/// the window state, while the admin's own "Mark My Attendance" screen did not:
/// its buttons stayed enabled after close, the tap hit the server, and the
/// server correctly answered "cannot mark, attendance window from xx to xx".
/// An enabled button that always fails is a defect, so the staff screen needs
/// exactly the SAME gate — and "exactly the same" must mean shared code, not a
/// second copy of the arithmetic that can drift from the server's rules.
///
/// ## The phone clock is untrusted
/// (Guidebook gotcha, and a shipped bug.) Every gate below prefers the SERVER's
/// `orgClockMinutes` — minutes since org-timezone midnight, captured when
/// `/meals/today` was fetched — advanced by the device time elapsed *since* that
/// fetch. A wrong device timezone or a skewed clock therefore cannot open or
/// close a window. Only when the payload carries no server clock (a cached
/// paint, or a pre-fix server) does it fall back to the phone clock, which is
/// the pre-existing legacy behaviour.
///
/// All members are pure functions — no state, no I/O, safe to call in `build`.
class AttendanceWindow {
  const AttendanceWindow._();

  /// The client's rendering of "this meal has no bounded window": always open.
  static bool _isAllDay(MealAttendanceWindow w) =>
      w.openTime == '00:00' && w.closeTime == '23:59';

  static int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  static TimeOfDay _parseTime(String hhmm) {
    final parts = hhmm.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
  }

  /// Server org-clock "now" (minutes since org midnight), advanced by the device
  /// time elapsed since [fetchedAt]. Null → the caller falls back to the phone
  /// clock.
  ///
  /// Monotonicity guard: a backwards clock jump or an ancient payload (screen
  /// resumed after >12 h) returns null rather than extrapolating nonsense.
  static int? _orgNowMinutes(MealModel meal, DateTime? fetchedAt) {
    final base = meal.orgClockMinutes;
    if (base == null || fetchedAt == null) return null;
    final elapsed = DateTime.now().difference(fetchedAt).inMinutes;
    if (elapsed < 0 || elapsed > 12 * 60) return null;
    return (base + elapsed) % (24 * 60);
  }

  /// True while the server ACCEPTS a mark: open ≤ now < close + grace.
  /// Grace marks are accepted server-side (FR-TIME-005), so the button must
  /// stay enabled through the grace period or members lose a legitimate window.
  static bool isOpen(MealModel meal, {DateTime? fetchedAt}) {
    final w = meal.attendanceWindow;
    if (_isAllDay(w)) return true;
    final openMinutes = _minutesOf(_parseTime(w.openTime));
    final closeMinutes = _minutesOf(_parseTime(w.closeTime));
    final orgNow = _orgNowMinutes(meal, fetchedAt);
    if (orgNow != null) {
      final grace = meal.graceMinutes ?? 0;
      return orgNow >= openMinutes && orgNow < closeMinutes + grace;
    }
    final nowMinutes = _minutesOf(TimeOfDay.now());
    return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
  }

  /// True once the window (incl. grace) has fully closed — the point at which a
  /// same-day CORRECTION becomes the only route to change the record.
  static bool isPast(MealModel meal, {DateTime? fetchedAt}) {
    final w = meal.attendanceWindow;
    if (_isAllDay(w)) return false;
    final closeMinutes = _minutesOf(_parseTime(w.closeTime));
    final orgNow = _orgNowMinutes(meal, fetchedAt);
    if (orgNow != null) {
      final grace = meal.graceMinutes ?? 0;
      return orgNow >= closeMinutes + grace;
    }
    final nowMinutes = _minutesOf(TimeOfDay.now());
    return nowMinutes > closeMinutes;
  }
}

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

  /// The canonical tri-state for [meal]: `'upcoming'` | `'open'` | `'closed'`,
  /// matching the server's own `getWindowState` vocabulary. `'open'` INCLUDES
  /// the grace period, because grace marks are accepted server-side
  /// (FR-TIME-005) — a button disabled during grace would cost a member a
  /// legitimate window.
  ///
  /// This is THE window decision for the whole app. [isOpen] and [isPast] are
  /// thin readings of it (used by the member card and the admin's Mark My
  /// Attendance screen); the admin group-attendance screen calls this directly
  /// because its UI is tri-state. Nothing else may re-derive this arithmetic: two
  /// copies that disagree is the defect this replaced (the admin screen had a
  /// hand-rolled copy that never consulted [MealModel.windowState] and pinned
  /// every all-day-shaped meal to 'open' forever, so its Present button stayed
  /// enabled and the tap was then refused 423 by the server).
  static String stateOf(MealModel meal, {DateTime? fetchedAt}) {
    // A server verdict of CLOSED is final; everything else defers to the clock.
    //
    // Why only 'closed' wins: `windowState` is a SNAPSHOT taken when
    // /meals/today was fetched, whereas the arithmetic below ADVANCES with
    // elapsed time. Letting a stale 'open' win would keep buttons enabled after
    // the window really closed (open the app at 09:50 on a 10:00 close and
    // Present would still be live at 10:05). 'closed' is safe in the other
    // direction because time only moves forward — a closed window never
    // reopens.
    if (meal.windowState == 'closed') return 'closed';

    final w = meal.attendanceWindow;
    if (_isAllDay(w)) {
      // No bounded window in this payload — either the meal genuinely has none
      // (FR-TIME-001: always open for the date) or the client defaulted to the
      // all-day shape because the field was absent. The server may still have
      // resolved an EFFECTIVE window (a per-day override), and its snapshot is
      // the only evidence we have, so defer to it rather than assuming open.
      return meal.windowState == 'upcoming' ? 'upcoming' : 'open';
    }

    final openMinutes = _minutesOf(_parseTime(w.openTime));
    final closeMinutes = _minutesOf(_parseTime(w.closeTime));
    // Server org-clock when we have it, phone clock only as the legacy fallback.
    final now = _orgNowMinutes(meal, fetchedAt) ?? _minutesOf(TimeOfDay.now());
    final grace = meal.graceMinutes ?? 0;
    if (now < openMinutes) return 'upcoming';
    // Close is EXCLUSIVE server-side (FR-TIME-002), hence `<` not `<=`.
    if (now < closeMinutes + grace) return 'open';
    return 'closed';
  }

  /// True while the server ACCEPTS a mark: open ≤ now < close + grace.
  static bool isOpen(MealModel meal, {DateTime? fetchedAt}) =>
      stateOf(meal, fetchedAt: fetchedAt) == 'open';

  /// True once the window (incl. grace) has fully closed — the point at which a
  /// same-day CORRECTION becomes the only route to change the record.
  static bool isPast(MealModel meal, {DateTime? fetchedAt}) =>
      stateOf(meal, fetchedAt: fetchedAt) == 'closed';
}

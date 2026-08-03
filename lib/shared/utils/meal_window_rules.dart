/// Live-Test-16 ISSUE-2 — client-side mirror of the server's attendance-window
/// invariant, so the admin gets IMMEDIATE feedback instead of a round-trip 422.
///
/// The backend (`window-conflict.util.ts`) remains the authority — this exists
/// purely for UX. Both sides implement exactly the same three rules:
///
///   1. every admin-configured window has BOTH an open and a close time;
///   2. `close > open` — a window opens and closes on the same calendar date
///      (overnight windows such as 23:00 → 01:00 are rejected);
///   3. windows applying to the same date never overlap and are separated by at
///      least [kMinWindowGapMinutes]:  next.open >= previous.close + gap.
///
/// Validation is LINEAR WITHIN A DATE — the next date is a new attendance
/// lifecycle, so today's last window is never compared with tomorrow's first.
///
/// Pure functions: no state, no I/O, safe to call inside `build`.
library;

/// Minimum minutes between one window's close and the next one's open.
/// Mirrors the server default (`MEALS_WINDOW_MIN_GAP_MINUTES`, default 60).
const int kMinWindowGapMinutes = 60;

/// The implicit system attendance slot — never an admin-created window, so it
/// is exempt from every rule here (matches the backend exemption).
const String kGeneralAttendanceSlotKey = '__general__';

/// One meal's effective window as the validator sees it.
class MealWindowRef {
  const MealWindowRef({
    required this.mealId,
    required this.label,
    this.slotKey,
    this.openTime,
    this.closeTime,
  });

  final String mealId;
  final String label;
  final String? slotKey;

  /// "HH:mm" — null/empty means "not configured", which is now invalid.
  final String? openTime;
  final String? closeTime;
}

/// "HH:mm" → minutes since midnight; null when missing or unparseable.
int? parseHHmm(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

String _to12h(int minutes) {
  final h24 = minutes ~/ 60;
  final m = minutes % 60;
  final suffix = h24 < 12 ? 'AM' : 'PM';
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h:${m.toString().padLeft(2, '0')} $suffix';
}

String _gapLabel(int gap) =>
    gap % 60 == 0 ? '${gap ~/ 60}-hour' : '$gap-minute';

/// Validates one date's set of windows.
///
/// Returns null when the set is valid, or a ready-to-show admin message naming
/// the conflicting meal, both windows and the earliest allowed start time.
String? validateMealWindows(
  List<MealWindowRef> windows, {
  int gapMinutes = kMinWindowGapMinutes,
}) {
  final parsed = <({MealWindowRef ref, int open, int close})>[];

  for (final w in windows) {
    if (w.slotKey == kGeneralAttendanceSlotKey) continue;
    final open = parseHHmm(w.openTime);
    final close = parseHHmm(w.closeTime);
    if (open == null || close == null) {
      return '"${w.label}" needs an attendance window — set both an opening '
          'and a closing time.';
    }
    if (close <= open) {
      return '"${w.label}" must open and close on the same day — the closing '
          'time has to be later than the opening time.';
    }
    parsed.add((ref: w, open: open, close: close));
  }

  if (parsed.length < 2) return null;
  parsed.sort((a, b) {
    final byOpen = a.open.compareTo(b.open);
    if (byOpen != 0) return byOpen;
    return a.close.compareTo(b.close);
  });

  // Compare against the LATEST close seen so far so a fully-contained window
  // (07:00–12:00 vs 08:00–09:00) is caught too.
  var boundary = parsed.first;
  for (var i = 1; i < parsed.length; i++) {
    final current = parsed[i];
    if (current.open < boundary.close) {
      return 'Attendance Window Conflict — "${current.ref.label}" '
          '(${_to12h(current.open)} – ${_to12h(current.close)}) overlaps '
          '"${boundary.ref.label}" (${_to12h(boundary.open)} – '
          '${_to12h(boundary.close)}). Two meals can never accept attendance '
          'at the same time.';
    }
    if (current.open - boundary.close < gapMinutes) {
      final earliest = boundary.close + gapMinutes;
      return '"${boundary.ref.label}" attendance ends at '
          '${_to12h(boundary.close)}. "${current.ref.label}" attendance cannot '
          'begin before ${_to12h(earliest)} because a minimum '
          '${_gapLabel(gapMinutes)} gap is required between different meal '
          'attendance windows.';
    }
    if (current.close > boundary.close) boundary = current;
  }
  return null;
}

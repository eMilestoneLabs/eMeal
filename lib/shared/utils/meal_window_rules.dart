/// Live-Test-16 ISSUE-2 — client-side mirror of the server's attendance-window
/// invariant, so the admin gets IMMEDIATE feedback instead of a round-trip 422.
///
/// The backend (`window-conflict.util.ts`) remains the authority — this exists
/// purely for UX. Both sides implement exactly the same two rules:
///
///   1. every admin-configured window has BOTH an open and a close time;
///   2. `close > open` — a window opens and closes on the same calendar date
///      (overnight windows such as 23:00 → 01:00 are rejected);
///
/// WITHDRAWN 2026-08-03 (user decision): the no-overlap rule and the minimum
/// 1-hour gap were removed. ANY NUMBER of CONCURRENT windows is allowed — a
/// group may open every meal 07:00-09:00 so members declare the whole day in
/// one morning session. Windows are therefore never compared with each other.
///
/// Pure functions: no state, no I/O, safe to call inside `build`.
library;

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

/// Accepted time shape — byte-for-byte the server's own
/// (`entry-chrono.util.ts`: `/^(\d{1,2}):(\d{2})$/`). Kept identical so the
/// client can never be MORE permissive than the backend: a looser split-based
/// parse accepts "7:5", "07:00:00" and " 07:00", which the server rejects —
/// the admin would be told the window is fine and then get a 422 on save.
final RegExp _kHHmm = RegExp(r'^(\d{1,2}):(\d{2})$');

/// "HH:mm" → minutes since midnight; null when missing or unparseable.
int? parseHHmm(String? value) {
  if (value == null) return null;
  final m = _kHHmm.firstMatch(value);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// Validates each window independently.
///
/// Returns null when every window is valid, or a ready-to-show admin message
/// naming the offending meal. Windows are NOT compared with one another —
/// concurrent windows are allowed.
String? validateMealWindows(List<MealWindowRef> windows) {
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
  }
  return null;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/utils/attendance_window.dart';

/// Live-Test-14 ISSUE-001 — the shared attendance-window gate.
///
/// This pure function decides whether the Present / Absent buttons are ENABLED
/// on both the member card and the admin's "Mark My Attendance" screen. A wrong
/// answer here either blocks a member from marking a meal they are entitled to,
/// or re-opens the original defect (an enabled button whose tap the server
/// always refuses). It had no test, so the rules are pinned here.
///
/// The phone clock is untrusted: whenever the payload carries the SERVER's
/// `orgClockMinutes`, it wins over the device wall clock.
MealModel meal({
  String open = '09:00',
  String close = '10:00',
  int? orgClockMinutes,
  int? graceMinutes,
  String? windowState,
}) {
  return MealModel(
    id: 'm1',
    groupId: 'g1',
    organizationId: 'o1',
    name: 'Lunch',
    slotKey: 'lunch',
    order: 1,
    isActive: true,
    attendanceWindow: MealAttendanceWindow(openTime: open, closeTime: close),
    orgClockMinutes: orgClockMinutes,
    graceMinutes: graceMinutes,
    windowState: windowState,
  );
}

void main() {
  group('all-day window (the client shape of "no bounded window")', () {
    test('00:00–23:59 is ALWAYS open and never past', () {
      final m = meal(open: '00:00', close: '23:59');
      // fetchedAt null → no server clock; must still be open regardless of the
      // device time, or attendance-only groups could never mark.
      expect(AttendanceWindow.isOpen(m), isTrue);
      expect(AttendanceWindow.isPast(m), isFalse);
    });

    test('stays open even when a server clock says 23:58', () {
      final m = meal(open: '00:00', close: '23:59', orgClockMinutes: 23 * 60 + 58);
      expect(AttendanceWindow.isOpen(m, fetchedAt: DateTime.now()), isTrue);
      expect(AttendanceWindow.isPast(m, fetchedAt: DateTime.now()), isFalse);
    });
  });

  group('server org-clock wins over the device clock', () {
    final fetchedAt = DateTime.now();

    test('inside the window → OPEN, not past', () {
      // Server says 09:30 on a 09:00–10:00 window.
      final m = meal(orgClockMinutes: 9 * 60 + 30);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isTrue);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isFalse);
    });

    test('before it opens → NOT open and NOT past (upcoming)', () {
      final m = meal(orgClockMinutes: 8 * 60);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isFalse);
    });

    test('after close → CLOSED and past (correction becomes the only route)', () {
      final m = meal(orgClockMinutes: 11 * 60);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
    });

    test('exactly AT close → closed (upper bound is exclusive)', () {
      final m = meal(orgClockMinutes: 10 * 60);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
    });

    test('exactly AT open → open (lower bound is inclusive)', () {
      final m = meal(orgClockMinutes: 9 * 60);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isTrue);
    });
  });

  group('grace period (FR-TIME-005 — the server still accepts these marks)', () {
    final fetchedAt = DateTime.now();

    test('inside grace → still OPEN and not yet past', () {
      // 10:05 with 10 minutes of grace on a 10:00 close.
      final m = meal(orgClockMinutes: 10 * 60 + 5, graceMinutes: 10);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isTrue);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isFalse);
    });

    test('past grace → closed', () {
      final m = meal(orgClockMinutes: 10 * 60 + 11, graceMinutes: 10);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
    });
  });

  group('monotonicity guard — never extrapolate a nonsense clock', () {
    test('elapsed time advances the server clock', () {
      // Server said 09:00; 30 device-minutes have passed → treat as 09:30.
      final m = meal(orgClockMinutes: 9 * 60);
      final fetchedAt = DateTime.now().subtract(const Duration(minutes: 30));
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isTrue);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isFalse);
    });

    test('elapsed time can carry the window past its close', () {
      final m = meal(orgClockMinutes: 9 * 60);
      final fetchedAt = DateTime.now().subtract(const Duration(minutes: 120));
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
    });

    // COVERAGE NOTE (honest limitation, found by mutation testing): the two
    // cases below do NOT isolate the `elapsed < 0 || elapsed > 12h` guard.
    // Deleting that guard leaves them green, because the extrapolated value
    // ((0 + 780) % 1440 = 13:00, and Dart's % makes -60 wrap to 23:00) is ALSO
    // past a 00:02 close — same verdict by a different route. Isolating the
    // guard would require asserting the phone-clock branch, whose answer depends
    // on the wall clock at run time; the util takes no injectable clock, so such
    // a test would be flaky. These therefore assert the weaker but still useful
    // property: a corrupt/ancient timestamp yields a SANE verdict and never
    // throws or produces a nonsense window state.
    test('an ancient payload still yields a sane verdict (no crash/nonsense)', () {
      final m = meal(open: '00:01', close: '00:02', orgClockMinutes: 0);
      final fetchedAt = DateTime.now().subtract(const Duration(hours: 13));
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
    });

    test('a backwards clock jump still yields a sane verdict', () {
      final m = meal(open: '00:01', close: '00:02', orgClockMinutes: 0);
      final fetchedAt = DateTime.now().add(const Duration(hours: 1));
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
    });

    test('no server clock at all → phone-clock fallback (legacy payloads)', () {
      final m = meal(open: '00:01', close: '00:02');
      expect(AttendanceWindow.isPast(m), isTrue);
      expect(AttendanceWindow.isOpen(m), isFalse);
    });
  });

  group('the three states are mutually exclusive', () {
    final fetchedAt = DateTime.now();

    test('a meal is never simultaneously open and past', () {
      for (final minutes in [0, 8 * 60, 9 * 60, 9 * 60 + 59, 10 * 60, 23 * 60]) {
        final m = meal(orgClockMinutes: minutes);
        final open = AttendanceWindow.isOpen(m, fetchedAt: fetchedAt);
        final past = AttendanceWindow.isPast(m, fetchedAt: fetchedAt);
        expect(open && past, isFalse, reason: 'both true at $minutes min');
      }
    });
  });

  group('SERVER windowState is authoritative (guidebook: /meals/today wins)', () {
    final fetchedAt = DateTime.now();

    test("'closed' beats an all-day window that would read as open", () {
      // THE Live-Test-14 defect: a meal with no configured window falls back to
      // the all-day 00:00-23:59 shape, so client arithmetic said OPEN and the
      // Present button stayed enabled — then the server refused the mark.
      final m = meal(open: '00:00', close: '23:59', windowState: 'closed');
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
    });

    test("'closed' beats a clock that is inside the window", () {
      final m = meal(orgClockMinutes: 9 * 60 + 30, windowState: 'closed');
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
    });

    test("a STALE 'open' must NOT keep a lapsed window open", () {
      // The rule is deliberately ONE-WAY. windowState is a snapshot; the clock
      // advances. A member who opened the app before the close must not still
      // see Present afterwards just because the cached verdict said 'open'.
      final m = meal(orgClockMinutes: 23 * 60, windowState: 'open');
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isTrue);
    });

    test("'open' inside the window stays open (clock agrees)", () {
      final m = meal(orgClockMinutes: 9 * 60 + 30, windowState: 'open');
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isTrue);
    });

    test("'upcoming' before the window is neither open nor past", () {
      final m = meal(orgClockMinutes: 8 * 60, windowState: 'upcoming');
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isFalse);
      expect(AttendanceWindow.isPast(m, fetchedAt: fetchedAt), isFalse);
    });

    test('a cached payload without windowState still uses the clock', () {
      final m = meal(orgClockMinutes: 9 * 60 + 30); // windowState null
      expect(AttendanceWindow.isOpen(m, fetchedAt: fetchedAt), isTrue);
    });
  });

  /// Live-Test-14 ISSUE-2 (re-report) — the tri-state the ADMIN attendance
  /// screen switches on. It used to compute this itself, with a copy that never
  /// consulted `windowState` and pinned the all-day shape to 'open' forever, so
  /// ONE meal kept an enabled Present button that the server then refused 423.
  group('stateOf — the canonical tri-state', () {
    test('all-day shape + server says CLOSED -> closed (THE re-reported bug)',
        () {
      // The meal whose payload carries no bounded window still has an EFFECTIVE
      // window server-side (a per-day override). Its snapshot is the only
      // evidence the client has, so it must win over the all-day assumption.
      final m = meal(open: '00:00', close: '23:59', windowState: 'closed');
      expect(AttendanceWindow.stateOf(m), 'closed');
      expect(AttendanceWindow.isOpen(m), isFalse,
          reason: 'Present/Absent must be DISABLED once the server says closed');
      expect(AttendanceWindow.isPast(m), isTrue,
          reason: 'and the same-day correction route must open instead');
    });

    test('all-day shape + server says UPCOMING -> upcoming (not open)', () {
      final m = meal(open: '00:00', close: '23:59', windowState: 'upcoming');
      expect(AttendanceWindow.stateOf(m), 'upcoming');
      expect(AttendanceWindow.isOpen(m), isFalse);
      expect(AttendanceWindow.isPast(m), isFalse,
          reason: 'upcoming is not closed — no correction route yet');
    });

    test('all-day shape with NO server verdict stays open (legacy fallback)',
        () {
      expect(AttendanceWindow.stateOf(meal(open: '00:00', close: '23:59')),
          'open');
    });

    test('bounded window: before open / inside / after close', () {
      final at = DateTime.now();
      String stateAt(int m) => AttendanceWindow.stateOf(
            meal(open: '09:00', close: '10:00', orgClockMinutes: m),
            fetchedAt: at,
          );
      expect(stateAt(8 * 60 + 59), 'upcoming');
      expect(stateAt(9 * 60), 'open', reason: 'open is INCLUSIVE');
      expect(stateAt(10 * 60), 'closed',
          reason: 'close is EXCLUSIVE server-side (FR-TIME-002)');
    });

    test('grace extends open, and only by the granted minutes', () {
      final at = DateTime.now();
      String stateAt(int m) => AttendanceWindow.stateOf(
            meal(
                open: '09:00',
                close: '10:00',
                orgClockMinutes: m,
                graceMinutes: 15),
            fetchedAt: at,
          );
      expect(stateAt(10 * 60 + 14), 'open',
          reason: 'grace marks are accepted server-side (FR-TIME-005)');
      expect(stateAt(10 * 60 + 15), 'closed');
    });

    test('a stale server "open" never keeps a lapsed window alive', () {
      // windowState is a SNAPSHOT; the clock advances. Only 'closed' is final.
      final m = meal(
          open: '09:00',
          close: '10:00',
          orgClockMinutes: 11 * 60,
          windowState: 'open');
      expect(AttendanceWindow.stateOf(m, fetchedAt: DateTime.now()), 'closed');
    });
  });

  /// Live-Test-14 ISSUE-2 — the cache must not silently disarm the gate.
  group('cache round-trip preserves the server window authority', () {
    test('toJson -> fromJson keeps windowState/orgClock/grace/orgDate', () {
      const live = MealModel(
        id: 'm1',
        groupId: 'g1',
        organizationId: 'o1',
        name: 'Lunch',
        slotKey: 'lunch',
        order: 1,
        isActive: true,
        attendanceWindow:
            MealAttendanceWindow(openTime: '09:00', closeTime: '10:00'),
        windowState: 'closed',
        orgClockMinutes: 11 * 60,
        graceMinutes: 15,
        orgDate: '2026-07-27',
      );

      final cached = MealModel.fromJson(live.toJson());

      expect(cached.windowState, 'closed');
      expect(cached.orgClockMinutes, 11 * 60);
      expect(cached.graceMinutes, 15);
      expect(cached.orgDate, '2026-07-27');
      // The whole point: the gate must reach the same verdict from cache.
      expect(AttendanceWindow.stateOf(cached), 'closed');
      expect(AttendanceWindow.isOpen(cached), isFalse,
          reason: 'a cached paint must NOT re-enable a closed meal');
    });
  });
}

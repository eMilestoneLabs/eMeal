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
}

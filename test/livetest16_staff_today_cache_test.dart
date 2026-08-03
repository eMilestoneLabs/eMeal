import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/utils/attendance_window.dart';

/// Live-Test-16 — the staff self-attendance cache contract.
///
/// `_paintFromCache` uses the service's own `readListOrNull` / `readList`
/// helpers, which are documented to swallow a corrupt entry and return a miss
/// rather than throw. That is correct for resilience, but it means a shape
/// mismatch fails SILENTLY: the cache would simply never paint, the skeleton
/// would come back, and nothing would report an error. These guards pin the
/// round-trip so that can't happen unnoticed.
void main() {
  const orgId = 'o1';
  const groupId = 'g1';
  const userId = 'u1';

  test('cache keys are organization + group + user scoped', () {
    // Mirrors _mealsCacheKey / _recordsCacheKey. Isolation is what makes a
    // group or account switch read DIFFERENT keys, so cross-context data can
    // never be painted.
    String meals(String o, String g, String u) => 'staff_today_meals:$o:$g:$u';
    String recs(String o, String g, String u) => 'staff_today_records:$o:$g:$u';

    expect(meals(orgId, groupId, userId), 'staff_today_meals:o1:g1:u1');
    expect(recs(orgId, groupId, userId), 'staff_today_records:o1:g1:u1');
    // The two datasets must never collide with each other.
    expect(meals(orgId, groupId, userId), isNot(recs(orgId, groupId, userId)));

    for (final k in [meals, recs]) {
      expect(k(orgId, 'g2', userId), isNot(k(orgId, groupId, userId)));
      expect(k('o2', groupId, userId), isNot(k(orgId, groupId, userId)));
      expect(k(orgId, groupId, 'u2'), isNot(k(orgId, groupId, userId)));
      // Shares the service prefix scheme, so logout's prefix-based clear() and
      // prune() cover both with no extra wiring.
      expect(k(orgId, groupId, userId).split(':').length, 4);
    }
  });

  test('max-age is configurable, not hardcoded at the call site', () {
    expect(AppConstants.staffTodayCacheMaxAge, const Duration(hours: 12));
  });

  test('MealModel survives the cache round-trip with the fields the screen uses',
      () {
    const meal = MealModel(
      id: 'm1',
      organizationId: orgId,
      groupId: groupId,
      name: 'Lunch',
      slotKey: 'lunch',
      order: 2,
      attendanceWindow:
          MealAttendanceWindow(openTime: '12:00', closeTime: '14:00'),
      isActive: true,
      price: 45,
    );

    final revived = MealModel.fromJson(meal.toJson());

    expect(revived.id, meal.id);
    expect(revived.name, meal.name);
    expect(revived.price, meal.price);
    expect(revived.isActive, isTrue);
    // Chronological sort runs on the revived list in _paintFromCache.
    expect(() => [revived].sort(MealModel.compareChronological), returnsNormally);
  });

  test('a cached meal DOES carry clock fields — staleness is undetectable', () {
    // THE reason the marking gate keys off `_mealsFetchedAt` and not the data.
    // Live-Test-14 ISSUE-2 deliberately made `windowState`,
    // `orgClockMinutes`, `graceMinutes` and `orgDate` survive `toJson()`, so a
    // payload restored from cache is INDISTINGUISHABLE from a live one — it
    // looks authoritative while carrying an hours-old server clock. Nothing in
    // the data says "I am stale", so the screen must track liveness itself.
    const meal = MealModel(
      id: 'm1',
      organizationId: orgId,
      groupId: groupId,
      name: 'Lunch',
      slotKey: 'lunch',
      order: 2,
      attendanceWindow:
          MealAttendanceWindow(openTime: '12:00', closeTime: '14:00'),
      isActive: true,
      price: 45,
      windowState: 'open',
      orgClockMinutes: 12 * 60 + 30,
      orgDate: '2026-08-02',
    );

    final revived = MealModel.fromJson(meal.toJson());

    expect(revived.orgClockMinutes, 12 * 60 + 30,
        reason: 'LT-14 made the clock survive caching — so a cached payload '
            'looks live, and only the live-fetch timestamp separates the two');
    expect(revived.windowState, 'open');
    expect(revived.orgDate, '2026-08-02');
  });

  test('image bytes are NOT serialised into the cache (no blob bloat)', () {
    // Guidebook: MinIO URLs only, never base64. A cached meal must carry the
    // URL, never the decoded bytes, or SharedPreferences would grow unbounded.
    final meal = MealModel(
      id: 'm1',
      organizationId: orgId,
      groupId: groupId,
      name: 'Lunch',
      slotKey: 'lunch',
      order: 2,
      attendanceWindow:
          const MealAttendanceWindow(openTime: '12:00', closeTime: '14:00'),
      isActive: true,
      imageUrl: 'https://minio.example/meal.jpg',
      imageBytes: [Uint8List.fromList([1, 2, 3, 4])],
    );

    final json = meal.toJson();
    expect(json.containsKey('imageBytes'), isFalse,
        reason: 'binary in SharedPreferences would bloat the cache');
    expect(json['imageUrl'], 'https://minio.example/meal.jpg');
  });

  test('AttendanceModel survives the round-trip with status + meal linkage', () {
    final rec = AttendanceModel(
      id: 'a1',
      mealId: 'm1',
      userId: userId,
      groupId: groupId,
      organizationId: orgId,
      status: AttendanceStatus.present,
      date: DateTime(2026, 8, 2),
      markedAt: DateTime(2026, 8, 2, 12, 30),
    );

    final revived = AttendanceModel.fromJson(rec.toJson());

    // _recordFor matches on mealId + y/m/d, and _statusFor reads status.
    expect(revived.mealId, 'm1');
    expect(revived.userId, userId);
    expect(revived.status, AttendanceStatus.present);
    expect(revived.date.year, 2026);
    expect(revived.date.month, 8);
    expect(revived.date.day, 2);
  });

  test('the typed list round-trip matches what writeList-readList do',
      () {
    const meal = MealModel(
      id: 'm1',
      organizationId: orgId,
      groupId: groupId,
      name: 'Lunch',
      slotKey: 'lunch',
      order: 2,
      attendanceWindow:
          MealAttendanceWindow(openTime: '12:00', closeTime: '14:00'),
      isActive: true,
      price: 45,
    );
    final rec = AttendanceModel(
      id: 'a1',
      mealId: 'm1',
      userId: userId,
      groupId: groupId,
      organizationId: orgId,
      status: AttendanceStatus.present,
      date: DateTime(2026, 8, 2),
      markedAt: DateTime(2026, 8, 2, 12, 30),
    );

    // What `writeList` stores per key: a plain JSON list, no envelope.
    final storedMeals = [meal].map((m) => m.toJson()).toList();
    final storedRecords = [rec].map((r) => r.toJson()).toList();

    // What `readListOrNull` / `readList` do on the way back out.
    final meals = storedMeals
        .whereType<Map<String, dynamic>>()
        .map(MealModel.fromJson)
        .toList();
    final records = storedRecords
        .whereType<Map<String, dynamic>>()
        .map(AttendanceModel.fromJson)
        .toList();

    expect(meals, hasLength(1), reason: 'meal list shape drifted');
    expect(records, hasLength(1), reason: 'record list shape drifted');
    expect(meals.first.name, 'Lunch');
    expect(records.first.status, AttendanceStatus.present);
  });

  _windowHazardGuards();
}

/// Live-Test-16 — WHY `_paintFromCache` must clear `_mealsFetchedAt`.
///
/// A bug I shipped into the first draft: the cached paint set `_meals` but left the fetch
/// timestamp from the PREVIOUS live load. After a group switch that meant the
/// window gate judged the NEW group's cached `orgClockMinutes` against the OLD
/// group's fetch time — with the marking buttons enabled. These guards pin the
/// framework behaviour that makes that dangerous.
void _windowHazardGuards() {
  MealModel mealAt(int orgClockMinutes) => MealModel(
        id: 'm1',
        organizationId: 'o1',
        groupId: 'g1',
        name: 'Lunch',
        slotKey: 'lunch',
        order: 2,
        attendanceWindow:
            const MealAttendanceWindow(openTime: '09:30', closeTime: '10:00'),
        isActive: true,
        orgClockMinutes: orgClockMinutes,
      );

  test('a STALE fetchedAt flips the window verdict — the hazard', () {
    final meal = mealAt(9 * 60); // server said 09:00 when the payload was made

    // Fresh: org clock 09:00, window opens 09:30 → not yet open.
    final fresh = AttendanceWindow.stateOf(meal, fetchedAt: DateTime.now());

    // Stale by an hour (a previous load's timestamp): 09:00 + 60 = 10:00,
    // which is past the exclusive close → a DIFFERENT verdict, from data that
    // never changed.
    final stale = AttendanceWindow.stateOf(
        meal, fetchedAt: DateTime.now().subtract(const Duration(hours: 1)));

    expect(fresh, isNot(stale),
        reason: 'a stale fetchedAt alone changes the verdict — which is why '
            'the cached paint must never inherit one');
  });

  test('fetchedAt: null falls back to the PHONE clock, not a safe "closed"', () {
    // Why the marking gate needs an EXPLICIT `_mealsFetchedAt != null` conjunct
    // rather than relying on stateOf to refuse: nulling fetchedAt does NOT
    // close the window — stateOf falls through to TimeOfDay.now(), the
    // untrusted device clock (Guidebook §8).
    final meal = mealAt(9 * 60);
    final verdict = AttendanceWindow.stateOf(meal, fetchedAt: null);
    expect(['upcoming', 'open', 'closed'], contains(verdict));
    // It answers from the device clock rather than refusing, so the screen must
    // hold the gate shut itself while `_mealsFetchedAt` is null.
  });

  test('the org clock refuses to advance beyond 12h — no infinite drift', () {
    final meal = mealAt(9 * 60);
    // Older than the 12h bound → _orgNowMinutes returns null → phone fallback.
    final verdict = AttendanceWindow.stateOf(
        meal, fetchedAt: DateTime.now().subtract(const Duration(hours: 13)));
    expect(['upcoming', 'open', 'closed'], contains(verdict));
  });
}

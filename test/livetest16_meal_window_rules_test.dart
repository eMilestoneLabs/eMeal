import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/utils/meal_window_rules.dart';

/// Live-Test-16 ISSUE-2 — the client mirror of the server's attendance-window
/// invariant. These assertions intentionally match the backend spec
/// (`window-and-pricing-lock.spec.ts`) case for case: if the two ever drift,
/// the admin sees a client error the server would allow, or vice versa.
void main() {
  MealWindowRef w(String id, String label, String? open, String? close,
          {String? slotKey}) =>
      MealWindowRef(
        mealId: id,
        label: label,
        slotKey: slotKey,
        openTime: open,
        closeTime: close,
      );

  group('validateMealWindows', () {
    test('accepts a valid same-day window', () {
      expect(validateMealWindows([w('m1', 'Breakfast', '07:00', '09:00')]),
          isNull);
    });

    test('rejects a missing window', () {
      expect(validateMealWindows([w('m1', 'Breakfast', null, null)]),
          contains('needs an attendance window'));
    });

    test('rejects an overnight window', () {
      expect(validateMealWindows([w('m1', 'Midnight Meal', '23:00', '01:00')]),
          contains('same day'));
    });

    // WITHDRAWN 2026-08-03: no-overlap and the 1-hour gap were removed, so any
    // number of concurrent windows is allowed.
    test('ALLOWS fully concurrent windows', () {
      expect(
        validateMealWindows([
          w('m1', 'Breakfast', '07:00', '09:00'),
          w('m2', 'Lunch', '07:00', '09:00'),
          w('m3', 'Dinner', '07:00', '09:00'),
        ]),
        isNull,
      );
    });

    test('ALLOWS overlap and sub-hour gaps', () {
      expect(
        validateMealWindows([
          w('m1', 'Breakfast', '07:00', '10:00'),
          w('m2', 'Lunch', '09:00', '12:00'),
          w('m3', 'Snack', '12:01', '13:00'),
        ]),
        isNull,
      );
    });

    test('still validates EVERY window in a concurrent set', () {
      expect(
        validateMealWindows([
          w('m1', 'Breakfast', '07:00', '09:00'),
          w('m2', 'Lunch', null, null),
        ]),
        contains('"Lunch" needs an attendance window'),
      );
    });

    // PARITY: the client must never be MORE permissive than the server's
    // `hhmmToMinutes` (/^(\d{1,2}):(\d{2})$/) — otherwise the form says the
    // window is fine and the save comes back 422. The time picker only emits
    // "HH:mm", so these forms are unreachable from the UI; the guard exists so
    // a future free-text field cannot silently reintroduce the drift.
    test('PARITY: rejects the exact forms the server rejects', () {
      for (final bad in ['7:5', '07:00:00', ' 07:00', '0700', '07:', ':00']) {
        expect(parseHHmm(bad), isNull, reason: '"$bad" must not parse');
      }
    });

    test('PARITY: accepts the exact forms the server accepts', () {
      expect(parseHHmm('07:00'), 7 * 60);
      expect(parseHHmm('7:00'), 7 * 60, reason: 'server allows a 1-digit hour');
      expect(parseHHmm('23:59'), 23 * 60 + 59);
      expect(parseHHmm('24:00'), isNull, reason: 'hour > 23 is invalid');
      expect(parseHHmm('07:60'), isNull, reason: 'minute > 59 is invalid');
    });

    test('exempts the implicit __general__ slot', () {
      expect(
        validateMealWindows([
          w('gen', 'Daily Attendance', null, null,
              slotKey: kGeneralAttendanceSlotKey),
          w('m1', 'Breakfast', '07:00', '09:00'),
        ]),
        isNull,
      );
    });
  });

  // Live-Test-16 ISSUE-1 — mealPricingLocked is SERVER-OWNED: it must survive
  // the SWR cache round-trip (or a cache-first paint would show the pricing
  // toggle as editable on a locked group) but must NEVER reach a request body
  // (the backend mealConfig DTO is whitelist + forbidNonWhitelisted → 422).
  group('mealPricingLocked cache/wire split', () {
    test('survives the cache round-trip (toJson → fromJson)', () {
      const cfg = GroupMealConfig(mealPricingLocked: true);
      expect(cfg.toJson()['mealPricingLocked'], isTrue);
      expect(
        GroupMealConfig.fromJson(cfg.toJson()).mealPricingLocked,
        isTrue,
        reason: 'a locked group must still read as locked from cache',
      );
    });

    test('is STRIPPED from the request body', () {
      const cfg = GroupMealConfig(mealPricingLocked: true);
      expect(cfg.toRequestJson().containsKey('mealPricingLocked'), isFalse);
    });

    test('request body is otherwise identical to the cache payload', () {
      // UNLOCKED group — the ordinary case, where the wire body must stay
      // byte-identical to the pre-Live-Test-16 payload. (A locked group
      // additionally drops the immutable mealPricingEnabled; see the L3 tests.)
      const cfg = GroupMealConfig(billingCycleChangeUsed: true);
      final wire = cfg.toRequestJson();
      // Strip the WHOLE server-owned set, not one hard-coded key — otherwise
      // this test goes stale the moment another display-only flag joins it
      // (exactly what happened when billingCycleChangeUsed was added).
      final cache = Map<String, dynamic>.from(cfg.toJson())
        ..removeWhere(
            (k, _) => GroupMealConfig.kServerOwnedMealConfigKeys.contains(k));
      expect(wire, equals(cache),
          reason: 'only server-owned flags may differ');
    });

    test('absent key parses as unlocked (older server / older cache)', () {
      expect(
        GroupMealConfig.fromJson(const {'mealsEnabled': true})
            .mealPricingLocked,
        isFalse,
      );
    });
  });

  // Pre-existing Pass-12 gap, closed with the same mechanism: the flag was
  // READ by fromJson but never WRITTEN by toJson, so a CONSUMED one-time
  // billing-cycle change came back from the SWR cache as still available.
  group('billingCycleChangeUsed cache/wire split', () {
    test('survives the cache round-trip (toJson → fromJson)', () {
      const cfg = GroupMealConfig(billingCycleChangeUsed: true);
      expect(cfg.toJson()['billingCycleChangeUsed'], isTrue);
      expect(
        GroupMealConfig.fromJson(cfg.toJson()).billingCycleChangeUsed,
        isTrue,
        reason: 'a consumed one-time change must stay consumed from cache',
      );
    });

    test('is STRIPPED from the request body', () {
      const cfg = GroupMealConfig(billingCycleChangeUsed: true);
      expect(
        cfg.toRequestJson().containsKey('billingCycleChangeUsed'),
        isFalse,
      );
    });

    // L3: a LOCKED group stops echoing the immutable pricing mode, so a stale
    // cached value can no longer 400 an unrelated toggle. An UNLOCKED group
    // must still send it (that is how the admin turns pricing on).
    test('L3: a LOCKED group does not echo mealPricingEnabled', () {
      const locked = GroupMealConfig(
        mealPricingEnabled: true,
        mealPricingLocked: true,
      );
      expect(locked.toRequestJson().containsKey('mealPricingEnabled'), isFalse);
    });

    test('L3: an UNLOCKED group still sends mealPricingEnabled', () {
      const unlocked = GroupMealConfig(mealPricingEnabled: true);
      expect(
        unlocked.toRequestJson()['mealPricingEnabled'],
        isTrue,
        reason: 'pre-publish the admin must still be able to enable pricing',
      );
    });

    test('no server-owned key ever reaches the wire', () {
      const cfg = GroupMealConfig(
        mealPricingLocked: true,
        billingCycleChangeUsed: true,
      );
      final wire = cfg.toRequestJson();
      for (final k in GroupMealConfig.kServerOwnedMealConfigKeys) {
        expect(wire.containsKey(k), isFalse, reason: '$k must not be sent');
      }
      // A locked group drops exactly ONE further key — the immutable pricing
      // mode (L3). Everything else still matches the cache payload.
      final cache = Map<String, dynamic>.from(cfg.toJson())
        ..removeWhere(
            (k, _) => GroupMealConfig.kServerOwnedMealConfigKeys.contains(k))
        ..remove('mealPricingEnabled');
      expect(wire, equals(cache));
    });
  });
}

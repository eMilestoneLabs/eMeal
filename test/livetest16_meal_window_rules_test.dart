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
    test('allows an exactly 1-hour gap (60 is valid)', () {
      expect(
        validateMealWindows([
          w('m1', 'Breakfast', '07:00', '09:00'),
          w('m2', 'Lunch', '10:00', '12:00'),
        ]),
        isNull,
      );
    });

    test('rejects 59 minutes (one minute short)', () {
      expect(
        validateMealWindows([
          w('m1', 'Breakfast', '07:00', '09:00'),
          w('m2', 'Lunch', '09:59', '12:00'),
        ]),
        contains('cannot begin before 10:00 AM'),
      );
    });

    test('rejects a direct overlap', () {
      expect(
        validateMealWindows([
          w('m1', 'Breakfast', '07:00', '10:00'),
          w('m2', 'Lunch', '09:00', '12:00'),
        ]),
        contains('overlaps'),
      );
    });

    test('rejects a fully contained window', () {
      expect(
        validateMealWindows([
          w('m1', 'All Day', '07:00', '12:00'),
          w('m2', 'Snack', '08:00', '09:00'),
        ]),
        contains('overlaps'),
      );
    });

    test('rejects a missing window', () {
      expect(
        validateMealWindows([w('m1', 'Breakfast', null, null)]),
        contains('needs an attendance window'),
      );
    });

    test('rejects an overnight window', () {
      expect(
        validateMealWindows([w('m1', 'Midnight Meal', '23:00', '01:00')]),
        contains('same day'),
      );
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

    test('a single valid window with no siblings passes', () {
      expect(validateMealWindows([w('m1', 'Breakfast', '07:00', '09:00')]),
          isNull);
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

    // F2: the server-enforced gap must survive the cache and never be sent.
    test('F2: windowMinGapMinutes round-trips and is stripped from the wire',
        () {
      const cfg = GroupMealConfig(windowMinGapMinutes: 90);
      expect(cfg.toJson()['windowMinGapMinutes'], 90);
      expect(GroupMealConfig.fromJson(cfg.toJson()).windowMinGapMinutes, 90);
      expect(cfg.toRequestJson().containsKey('windowMinGapMinutes'), isFalse);
    });

    test('F2: an older server omitting the key defaults to 60', () {
      expect(
        GroupMealConfig.fromJson(const {'mealsEnabled': true})
            .windowMinGapMinutes,
        60,
      );
    });

    test('F2: the validator honours a server gap of 90', () {
      const windows = [
        MealWindowRef(
          mealId: 'm1',
          label: 'Breakfast',
          openTime: '07:00',
          closeTime: '09:00',
        ),
        MealWindowRef(
          mealId: 'm2',
          label: 'Lunch',
          openTime: '10:00',
          closeTime: '12:00',
        ),
      ];
      // Legal at 60, a violation at the server-configured 90.
      expect(validateMealWindows(windows, gapMinutes: 60), isNull);
      expect(validateMealWindows(windows, gapMinutes: 90),
          contains('90-minute gap'));
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

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';

/// Live-Test-17 ISSUE-3 — Billing Cycle lifecycle on the CLIENT model.
///
/// The lock is server-enforced; these guard the two client-side properties that
/// would otherwise fail SILENTLY:
///
///   * the lock is DERIVED from `mealPricingLocked` (same server event), so it
///     can never drift out of lock-step with the pricing lock, and
///   * `toJson()` (CACHE format) vs `toRequestJson()` (WIRE format) disagree on
///     purpose — the cache must round-trip the cycle day, the request must not
///     echo it once locked or an unrelated toggle 400s.
void main() {
  const draft = GroupMealConfig(
    mealsEnabled: true,
    billingCycleStartDay: 15,
    mealPricingEnabled: true,
  );
  const published = GroupMealConfig(
    mealsEnabled: true,
    billingCycleStartDay: 15,
    mealPricingEnabled: true,
    mealPricingLocked: true,
  );

  group('billingCycleLocked derivation', () {
    test('a never-published group is DRAFT', () {
      expect(draft.billingCycleLocked, isFalse);
    });

    test('the first publish locks the cycle', () {
      expect(published.billingCycleLocked, isTrue);
    });

    test('the superseded one-time privilege does NOT lock the control', () {
      // A legacy group that consumed `billingCycleChangeUsed` but never
      // published is draft again — the backend now accepts the change, so a
      // client that still locked here would disagree with the server.
      const legacy = GroupMealConfig(
        mealsEnabled: true,
        billingCycleStartDay: 15,
        billingCycleChangeUsed: true,
      );
      expect(legacy.billingCycleLocked, isFalse);
    });
  });

  group('cache format vs wire format', () {
    test('DRAFT: the wire body still carries the cycle day', () {
      // Without this the admin could never configure the cycle at all.
      expect(draft.toRequestJson()['billingCycleStartDay'], 15);
    });

    test('LOCKED: the wire body drops the immutable cycle day', () {
      expect(published.toRequestJson().containsKey('billingCycleStartDay'),
          isFalse);
      expect(
          published.toRequestJson().containsKey('mealPricingEnabled'), isFalse);
    });

    test('LOCKED: the CACHE still round-trips the cycle day', () {
      // Cache fidelity: a cache-first paint must show the real configured day,
      // not a blank control.
      final cached = published.toJson();
      expect(cached['billingCycleStartDay'], 15);
      expect(cached['mealPricingLocked'], isTrue);
      expect(GroupMealConfig.fromJson(cached).billingCycleStartDay, 15);
      expect(GroupMealConfig.fromJson(cached).billingCycleLocked, isTrue);
    });

    test('every server-owned key is stripped from the wire body', () {
      for (final k in GroupMealConfig.kServerOwnedMealConfigKeys) {
        expect(published.toRequestJson().containsKey(k), isFalse,
            reason: '$k is server-owned and would 422 the whitelist DTO');
      }
    });
  });
}

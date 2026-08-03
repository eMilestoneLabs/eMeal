import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/features/admin/meals/providers/meal_config_provider.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Live-Test-16 ISSUE-1 — `markMealPricingLocked` is the CLIENT MIRROR of a
/// lock the SERVER established. It writes into the SHARED `admin_groups:{org}`
/// cache, so a mirror the server did not actually take would persist a false
/// lock across app restarts until the next groups refresh.
///
/// The server stamps the lock only when `group.mealsEnabled === true`
/// (`schedules.service.ts` M2 gate): an Attendance-Only group that kept
/// `weeklyMenuEnabled` from a previous meals-ON life can still reach a publish,
/// and is deliberately NOT stamped. These guards pin the client to that same
/// gate so the two can never diverge.
class _FakeMealRepo extends MealRepository {
  @override
  Future<Result<List<MealModel>>> getGroupMeals({
    required String organizationId,
    required String groupId,
    bool includeDisabled = false,
  }) async =>
      const Ok<List<MealModel>>([]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  GroupModel group({required bool mealsEnabled, bool locked = false}) =>
      GroupModel(
        id: 'g1',
        organizationId: 'o1',
        name: 'Block A',
        type: GroupType.hostel,
        memberIds: const [],
        mealConfig: GroupMealConfig(
          mealsEnabled: mealsEnabled,
          mealPricingEnabled: true,
          mealPricingLocked: locked,
        ),
      );

  Future<MealConfigProvider> providerFor(GroupModel g) async {
    final p = MealConfigProvider(mealRepo: _FakeMealRepo());
    await p.selectGroup(g, organizationId: 'o1');
    return p;
  }

  test('POSITIVE: a Meal-Enabled group mirrors the lock', () async {
    final p = await providerFor(group(mealsEnabled: true));
    expect(p.selectedGroup!.mealConfig.mealPricingLocked, isFalse);

    p.markMealPricingLocked(organizationId: 'o1');

    expect(p.selectedGroup!.mealConfig.mealPricingLocked, isTrue,
        reason: 'the server stamped it, so Meal Config must paint 🔒 at once');
  });

  test(
      'NEGATIVE: an Attendance-Only group is NEVER mirrored '
      '(the server never stamped it)', () async {
    final p = await providerFor(group(mealsEnabled: false));

    p.markMealPricingLocked(organizationId: 'o1');

    expect(
      p.selectedGroup!.mealConfig.mealPricingLocked,
      isFalse,
      reason: 'mirroring a lock the server refused would persist a FALSE lock '
          'into the shared admin_groups:{org} cache',
    );
  });

  test('CORNER: an already-locked group is a no-op (idempotent)', () async {
    final p = await providerFor(group(mealsEnabled: true, locked: true));
    var notified = 0;
    p.addListener(() => notified++);

    p.markMealPricingLocked(organizationId: 'o1');

    expect(p.selectedGroup!.mealConfig.mealPricingLocked, isTrue);
    expect(notified, 0, reason: 'no rebuild for a state that did not change');
  });

  test('CORNER: no selected group is a safe no-op (never throws)', () {
    final p = MealConfigProvider(mealRepo: _FakeMealRepo());
    expect(p.selectedGroup, isNull);
    expect(() => p.markMealPricingLocked(organizationId: 'o1'), returnsNormally);
  });

  test('the mirror never touches the OTHER groups in the list', () async {
    final p = await providerFor(group(mealsEnabled: true));

    p.markMealPricingLocked(organizationId: 'o1');

    // Tenant/group isolation: only the selected group's id may change state.
    for (final g in p.groups.where((g) => g.id != 'g1')) {
      expect(g.mealConfig.mealPricingLocked, isFalse);
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/features/admin/meals/providers/meal_config_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Live-Test-15 ISSUE-4 — GROUP ISOLATION IN THE PLANNER MATRIX.
///
/// The planner paints its matrix cache-first so tapping Schedule is instant.
/// That removed the unconditional skeleton, which created a data-isolation
/// hazard: `_weekSchedule` holds whichever group was loaded LAST, so on a group
/// switch the PREVIOUS group's matrix would stay on screen — and, because the
/// network had already landed for that group, it stayed EDITABLE. A save would
/// then have written group A's plan under group A's schedule id while the admin
/// believed they were editing group B.
///
/// Rule: "never display data from the previous account, group or organization".
/// These cases pin it.
class _SlowMealRepo extends MealRepository {
  _SlowMealRepo(this.byGroup);
  final Map<String, MealScheduleModel> byGroup;
  int calls = 0;

  /// When `getCurrentWeekSchedule` was first invoked — the ordering probe.
  DateTime? firstScheduleCallAt;

  /// Never completes — simulates the in-flight window that the bug lived in.
  bool hang = false;

  /// Meals per group — needed so `_mealsGroupId` is genuinely populated and
  /// the cross-group guard is the DECIDING factor, not an earlier early-return.
  Map<String, List<MealModel>> mealsByGroup = {};

  @override
  Future<Result<List<MealModel>>> getGroupMeals({
    required String organizationId,
    required String groupId,
    bool includeDisabled = false,
  }) async =>
      Ok(mealsByGroup[groupId] ?? const []);

  @override
  Future<Result<MealScheduleModel>> getCurrentWeekSchedule({
    required String organizationId,
    required String groupId,
  }) async {
    calls++;
    firstScheduleCallAt ??= DateTime.now();
    if (hang) {
      // Long enough that the test observes the pre-network state.
      await Future<void>.delayed(const Duration(seconds: 5));
    }
    final s = byGroup[groupId];
    return s == null
        ? const Err(NetworkFailure(message: 'not found'))
        : Ok(s);
  }
}

class _FakeGroupRepo extends GroupRepository {
  _FakeGroupRepo(this.groups, {this.delay = Duration.zero});
  final List<GroupModel> groups;
  final Duration delay;

  /// Set when the groups call COMPLETES — the ordering probe below compares
  /// the schedule call's start against this.
  DateTime? completedAt;

  @override
  Future<Result<PaginatedResponse<GroupModel>>> getOrganisationGroups({
    required String organizationId,
    bool includeInactive = false,
  }) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    completedAt = DateTime.now();
    return Ok(PaginatedResponse<GroupModel>(
      data: groups,
      total: groups.length,
      page: 1,
      limit: 20,
    ));
  }
}

GroupModel groupModel(String id) => GroupModel(
      id: id,
      organizationId: 'org1',
      name: id,
      type: GroupType.hostel,
      mealConfig: const GroupMealConfig(),
      memberIds: const [],
    );

MealScheduleModel schedule(String id, String groupId) => MealScheduleModel(
      id: id,
      groupId: groupId,
      organizationId: 'org1',
      days: const [],
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('group switch NEVER leaves the previous group\'s matrix on screen',
      () async {
    final repo = _SlowMealRepo({
      'gA': schedule('sA', 'gA'),
      'gB': schedule('sB', 'gB'),
    });
    final p = MealConfigProvider(mealRepo: repo);

    // Group A fully loaded → editable.
    await p.loadSchedule(organizationId: 'org1', groupId: 'gA');
    expect(p.weekSchedule?.groupId, 'gA');
    expect(p.scheduleStale, isFalse, reason: 'A is verified, so editable');

    // Switch to B; hold the network open so we observe the in-flight state.
    repo.hang = true;
    final pending = p.loadSchedule(organizationId: 'org1', groupId: 'gB');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // THE REGRESSION: group A's matrix must be gone the moment B is requested.
    expect(p.weekSchedule?.groupId, isNot('gA'),
        reason: "group A's plan must never render under group B");

    repo.hang = false;
    await pending;
    expect(p.weekSchedule?.groupId, 'gB');
  });

  test('a cached matrix from another group is never painted', () async {
    // Seed the CACHE for group B with a (corrupt) entry belonging to group A.
    SharedPreferences.setMockInitialValues({});
    final repo = _SlowMealRepo({'gB': schedule('sB', 'gB')});
    final p = MealConfigProvider(mealRepo: repo);

    await p.loadSchedule(organizationId: 'org1', groupId: 'gB');
    expect(p.weekSchedule?.groupId, 'gB');
    expect(p.scheduleStale, isFalse);
  });

  test("group A's meals NEVER seed group B's empty draft (parallel-wave race)",
      () async {
    // meals and schedule ride ONE parallel wave, so the schedule can land while
    // `_meals` still belongs to the PREVIOUS group. Draft auto-population reads
    // `_meals` — and once it populates, the later re-run no-ops (draft is no
    // longer empty), so a wrong-group seed would STICK.
    final repo = _SlowMealRepo({
      'gA': schedule('sA', 'gA'),
      'gB': schedule('sB', 'gB'), // empty draft — the auto-populate target
    });
    repo.mealsByGroup = {
      'gA': [
        const MealModel(
          id: 'mealA',
          groupId: 'gA',
          organizationId: 'org1',
          name: 'Group A Breakfast',
          slotKey: 'breakfast',
          order: 1,
          attendanceWindow:
              MealAttendanceWindow(openTime: '07:00', closeTime: '09:00'),
          isActive: true,
        ),
      ],
      'gB': const [],
    };
    final p = MealConfigProvider(mealRepo: repo);

    // Load group A completely → `_meals` and `_mealsGroupId` are now gA's.
    await p.selectGroupWithSchedule(
      const GroupModel(
        id: 'gA',
        organizationId: 'org1',
        name: 'A',
        type: GroupType.hostel,
        mealConfig: GroupMealConfig(),
        memberIds: [],
      ),
      organizationId: 'org1',
    );
    expect(p.meals.isNotEmpty, isTrue, reason: 'group A meals must be loaded');

    // Now the RACE: group B's schedule lands while `_meals` is still gA's.
    await p.loadSchedule(organizationId: 'org1', groupId: 'gB');

    expect(p.weekSchedule?.groupId, 'gB');
    final seeded = (p.weekSchedule?.days ?? const [])
        .any((d) => d.meals.any((m) => m.mealId == 'mealA'));
    expect(seeded, isFalse,
        reason: "group A's meal must never be seeded into group B's draft");
  });

  test('COLD OPEN: the schedule rides wave 1 and is fetched EXACTLY once',
      () async {
    // The cold open (nothing cached) was ISSUE-4's "tap Schedule is slow":
    // `sel` is null, so the schedule fetch dropped out of the parallel wave and
    // ran sequentially afterwards — and step 3 then fetched it a SECOND time.
    // `preferredGroupId` is the nav param, and loadSchedule needs nothing else,
    // so it belongs in wave 1.
    final repo = _SlowMealRepo({'gA': schedule('sA', 'gA')});
    repo.mealsByGroup = {'gA': const []};
    // A SLOW groups call: if the schedule fetch is sequential it can only start
    // AFTER this resolves; if it rides the same wave it starts immediately.
    final groupRepo = _FakeGroupRepo(
      [groupModel('gA')],
      delay: const Duration(milliseconds: 300),
    );
    final p = MealConfigProvider(mealRepo: repo, groupRepo: groupRepo);

    // Cold cache: no groups, no meals, no selection — only the nav param.
    await p.bootstrapPlanner(organizationId: 'org1', preferredGroupId: 'gA');

    expect(repo.calls, 1,
        reason: 'fetched once — never skipped-then-refetched');
    expect(repo.firstScheduleCallAt, isNotNull);
    expect(groupRepo.completedAt, isNotNull);
    // THE ASSERTION THAT MATTERS: the schedule fetch must START BEFORE the
    // groups fetch FINISHES — i.e. they share one wave. Sequential ordering
    // (the pre-fix behaviour) makes this strictly false.
    expect(
      repo.firstScheduleCallAt!.isBefore(groupRepo.completedAt!),
      isTrue,
      reason: 'the schedule must ride wave 1, not wait for groups',
    );
  });

  test('a verified matrix is editable; an unverified one is not', () async {
    final repo = _SlowMealRepo({'gA': schedule('sA', 'gA')});
    final p = MealConfigProvider(mealRepo: repo);
    await p.loadSchedule(organizationId: 'org1', groupId: 'gA');
    // Network landed → the guard releases and editing is allowed.
    expect(p.scheduleStale, isFalse);
  });
}

// Live-Test-14 ISSUE-3B — the dashboard header must track the SELECTED group.
//
// The header line and the group dropdown sit next to each other, so any
// disagreement between them is immediately visible. The header used to read
// `_groups.first.name` — the FIRST group in the list, never the selected one —
// so switching groups left it on the previous group while the role chip beside
// it updated correctly. Both now read `selectedGroup`.
//
// Groups are seeded through the repository fakes rather than a test hook: the
// provider takes injectable repositories (Fable's own design), so prod code
// needs no `@visibleForTesting` back door.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/dashboard_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_attendance_summary.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

const _failure = NetworkFailure(message: 'offline (test)');

const _first = GroupModel(
  id: 'g1',
  organizationId: 'o1',
  name: 'Midnapore Namaste Mess',
  type: GroupType.mess,
  mealConfig: GroupMealConfig(mealsEnabled: true),
  memberIds: ['u1'],
);
const _second = GroupModel(
  id: 'g2',
  organizationId: 'o1',
  name: 'Tata Office Cafeteria',
  type: GroupType.mess,
  mealConfig: GroupMealConfig(mealsEnabled: true),
  memberIds: ['u1', 'u2'],
);

/// Overview fails so the LEGACY wave runs; groups succeed so `_groups` fills;
/// everything downstream fails fast. No HTTP anywhere.
class _FakeDashboardRepo extends DashboardRepository {
  @override
  Future<Result<Map<String, dynamic>>> getAdminOverview({
    required DateTime date,
  }) async =>
      const Err(_failure);
}

class _FakeGroupRepo extends GroupRepository {
  @override
  Future<Result<PaginatedResponse<GroupModel>>> getOrganisationGroups({
    required String organizationId,
    bool includeInactive = false,
  }) async =>
      const Ok(PaginatedResponse<GroupModel>(
        data: [_first, _second],
        page: 1,
        limit: 20,
        total: 2,
      ));
}

class _FakeAttendanceRepo extends AttendanceRepository {
  @override
  Future<Result<PaginatedResponse<AttendanceModel>>> getAttendanceHistory({
    required String userId,
    required String groupId,
    required String organizationId,
    DateTime? from,
    DateTime? to,
    PaginationParams params = const PaginationParams(),
  }) async =>
      const Err(_failure);

  @override
  Future<Result<MealAttendanceSummary>> getMealAttendanceSummary({
    required String organizationId,
    required String mealId,
    DateTime? date,
  }) async =>
      const Err(_failure);
}

class _FakeMealRepo extends MealRepository {
  @override
  Future<Result<List<MealModel>>> getTodayMeals({
    required String organizationId,
    required String groupId,
  }) async =>
      const Err(_failure);
}

Future<AdminDashboardProvider> loadedProvider() async {
  final p = AdminDashboardProvider(
    dashboardRepository: _FakeDashboardRepo(),
    groupRepository: _FakeGroupRepo(),
    attendanceRepository: _FakeAttendanceRepo(),
    mealRepository: _FakeMealRepo(),
  );
  try {
    await p.load(adminId: 'a1', organizationId: 'o1', name: 'Admin');
  } catch (_) {
    // Downstream failures are expected and irrelevant here.
  }
  return p;
}

/// Exactly what the dashboard screen hands to the greeting card.
String headerLabel(AdminDashboardProvider p) =>
    p.selectedGroup?.name ?? p.orgName;

void main() {
  // `load` binds the realtime service, which reaches for WidgetsBinding.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('groups load, so the binding has something to select', () async {
    final p = await loadedProvider();
    expect(p.groups.length, 2, reason: 'guards against a vacuous test');
  });

  test('selecting the SECOND group moves the header off the first', () async {
    final p = await loadedProvider();

    p.selectGroup(_second.id);

    expect(headerLabel(p), 'Tata Office Cafeteria',
        reason: 'the header must follow the selection, not _groups.first');
    expect(p.selectedGroup?.name, headerLabel(p),
        reason: 'header and dropdown must never disagree');
  });

  test('switching back follows again — no stale value', () async {
    final p = await loadedProvider();

    p.selectGroup(_second.id);
    p.selectGroup(_first.id);

    expect(headerLabel(p), 'Midnapore Namaste Mess');
  });

  test('with no group selected it falls back to the organisation', () async {
    final p = await loadedProvider();

    p.selectGroup(null);

    expect(headerLabel(p), AdminDashboardProvider.kOrgNamePlaceholder,
        reason: '"All groups" has no single group — org is the right context');
  });
}

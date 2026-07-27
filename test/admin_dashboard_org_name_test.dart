// Live-Test-14 ISSUE-3A — the organisation name must survive a reload.
//
// `AdminDashboardProvider.load` takes `organizationName` with a PLACEHOLDER
// default, and no caller can supply a real one (the user payload carries only
// organizationId). Assigning it unconditionally wiped an already-resolved name
// on every load, pull-to-refresh, refresh-button tap and error retry — the
// header fell back to "Your Organisation" while the spinner ran.
//
// Fixing the call sites one at a time was NOT enough: `refresh()` forwards to
// `load()` with the same default, and that path was missed. The guard therefore
// lives inside `load()`, and this test pins it there so no future caller —
// however it is wired — can reintroduce the wipe.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/repositories/dashboard_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Both repositories fail, so `load` takes its overview-then-legacy path and
/// exits at the groups error — no HTTP, no timeout. Every assertion below is
/// about the organisation name, which `load` assigns BEFORE any request.
const _failure = NetworkFailure(message: 'offline (test)');

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
      const Err(_failure);
}

AdminDashboardProvider makeProvider() => AdminDashboardProvider(
      dashboardRepository: _FakeDashboardRepo(),
      groupRepository: _FakeGroupRepo(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> settle(Future<void> f) async {
    try {
      await f;
    } catch (_) {
      // Irrelevant to this contract.
    }
  }

  test('a real organisation name is adopted', () async {
    final p = makeProvider();
    await settle(p.load(
      adminId: 'a1',
      organizationId: 'o1',
      name: 'Admin',
      organizationName: 'Acme Mess',
    ));

    expect(p.orgName, 'Acme Mess');
  });

  test('a later load WITHOUT a name must not wipe it', () async {
    final p = makeProvider();
    await settle(p.load(
      adminId: 'a1',
      organizationId: 'o1',
      name: 'Admin',
      organizationName: 'Acme Mess',
    ));
    expect(p.orgName, 'Acme Mess');

    // Exactly what the dashboard screen does — no organizationName argument.
    await settle(p.load(adminId: 'a1', organizationId: 'o1', name: 'Admin'));

    expect(p.orgName, 'Acme Mess',
        reason: 'the placeholder default must never overwrite a real name');
  });

  test('refresh() must not wipe it either — the path that was missed',
      () async {
    final p = makeProvider();
    await settle(p.load(
      adminId: 'a1',
      organizationId: 'o1',
      name: 'Admin',
      organizationName: 'Acme Mess',
    ));

    // Pull-to-refresh / refresh button / error retry all land here.
    await settle(p.refresh(
      adminId: 'a1',
      organizationId: 'o1',
      name: 'Admin',
    ));

    expect(p.orgName, 'Acme Mess',
        reason: 'refresh forwards to load with the same placeholder default');
  });

  test('until a real name is known the neutral placeholder shows', () async {
    final p = makeProvider();

    // Never a group name: the header must not invent an organisation.
    expect(p.orgName, AdminDashboardProvider.kOrgNamePlaceholder);

    await settle(p.load(adminId: 'a1', organizationId: 'o1', name: 'Admin'));

    expect(p.orgName, AdminDashboardProvider.kOrgNamePlaceholder);
  });
}

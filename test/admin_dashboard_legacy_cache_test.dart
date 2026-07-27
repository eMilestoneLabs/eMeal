// Live-Test-14 ISSUE-3A — the UPGRADE path.
//
// Isolated in its own file on purpose: ResponseCacheService memoises its
// SharedPreferences handle, and `flutter test` shares one isolate per FILE, so
// seeding a legacy cache entry mid-file never reaches the service. A fresh
// isolate is the only way this test is not vacuously green — which it was on
// the first attempt, and mutation testing is what exposed that.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/repositories/dashboard_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

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

Future<void> settle(Future<void> f) async {
  try {
    await f;
  } catch (_) {
    // Irrelevant to this contract.
  }
}

void main() {

  test('a legacy cache holding a GROUP name is not resurrected on upgrade',
      () async {
    // Builds before this fix wrote the group-name / "N Groups" substitution
    // into the old `orgName` cache key. An upgrading device still holds that
    // value, and restoring it would put a GROUP name back into the
    // Organisation field on the first cold paint — the exact reported defect.
    // Real ResponseCacheService shape: 'swr:' prefix, {__ts, __v} envelope.
    final legacy = jsonEncode({
      '__ts': DateTime.now().millisecondsSinceEpoch,
      '__v': {
        'orgName': 'Midnapore Namaste Mess', // what the OLD build wrote
        'groups': <dynamic>[],
        'meals': <dynamic>[],
        'activity': <dynamic>[],
        'mealSummaries': <dynamic>[],
      },
    });
    SharedPreferences.setMockInitialValues({'swr:admin_dashboard:o1': legacy});

    final p = makeProvider();
    await settle(p.load(adminId: 'a1', organizationId: 'o1', name: 'Admin'));

    expect(p.orgName, isNot('Midnapore Namaste Mess'),
        reason: 'the legacy key must be ignored, not restored');
    expect(p.orgName, AdminDashboardProvider.kOrgNamePlaceholder);
  });
}

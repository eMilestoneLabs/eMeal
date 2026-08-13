// Phase 1 wiring guard: the STUDENT SHELL resolves vacation per group.
//
// test/vacation_group_scope_resolution_test.dart pins the shared RULE. This
// file pins that StudentDashboardProvider actually USES it — a mutant that
// reverts the provider to the raw `user.isVacationMode` compiles cleanly and
// passes every rule test, so without this the wiring is unguarded.
//
// `isVacationMode` on this provider is what Attendance, Today's Meals, the
// greeting banner and reminder scheduling all read, so this one value decides
// whether a member can mark a meal.
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/student/dashboard/providers/student_dashboard_provider.dart';
import 'package:smart_meal_management/features/student/providers/group_config_provider.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

UserModel _user({required bool flag, List<String>? scope}) =>
    UserModel.fromJson({
      'id': 'u1',
      'name': 'A',
      'role': 'student',
      'isVacationMode': flag,
      if (scope != null) 'vacationScopedGroupIds': scope,
    });

StudentDashboardProvider _shellOnGroup(
  String groupId, {
  MemberSettingOverrides? overrides,
}) {
  final scope = GroupConfigProvider()
    ..update(
      config: const GroupMealConfig(),
      groupName: groupId,
      groupId: groupId,
    );
  if (overrides != null) scope.setMemberSettings(overrides);
  return StudentDashboardProvider(groupConfigProvider: scope);
}

void main() {
  group('student shell resolves vacation FOR THE CURRENT GROUP', () {
    test('THE BLOCKER: group-A leave does not gate marking in group B', () {
      final shell = _shellOnGroup('grp_B');
      shell.syncVacationFromUser(_user(flag: true, scope: ['grp_A']));
      // A raw `user.isVacationMode` here would be TRUE and would disable the
      // Attendance action card + Today's Meals for a group the member never
      // requested leave from — while the server accepts the mark.
      expect(shell.isVacationMode, isFalse);
    });

    test('the group the leave IS for still shows vacation', () {
      final shell = _shellOnGroup('grp_A');
      shell.syncVacationFromUser(_user(flag: true, scope: ['grp_A']));
      expect(shell.isVacationMode, isTrue);
    });

    test('BASELINE: org-wide vacation (null scope) still gates every group', () {
      for (final g in ['grp_A', 'grp_B']) {
        final shell = _shellOnGroup(g);
        shell.syncVacationFromUser(_user(flag: true));
        expect(shell.isVacationMode, isTrue, reason: g);
      }
    });

    test('BASELINE: no vacation stays off', () {
      final shell = _shellOnGroup('grp_A');
      shell.syncVacationFromUser(_user(flag: false));
      expect(shell.isVacationMode, isFalse);
    });

    test('an explicit per-group override wins over the account flag', () {
      final shell = _shellOnGroup(
        'grp_A',
        overrides: const MemberSettingOverrides(isVacationMode: false),
      );
      shell.syncVacationFromUser(_user(flag: true));
      expect(shell.isVacationMode, isFalse);
    });

    test('no group bound yet falls back to the account flag, never guesses off', () {
      // Deep-link before the shell scope resolves: hiding a real vacation
      // would let the member mark meals they are on leave for.
      final shell = StudentDashboardProvider();
      shell.syncVacationFromUser(_user(flag: true, scope: ['grp_A']));
      expect(shell.isVacationMode, isTrue);
    });
  });
}

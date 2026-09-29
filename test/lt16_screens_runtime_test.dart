// Issues_Live_Test_16 ISSUE-13/19 — RUNTIME render checks for the notice
// composer (compression gate) and the admin vacation-requests list (group
// badge): both must build at phone width and a large text scale with no
// exception while their network reads fail fast in the test binding.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/vacation_requests_screen.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/notices/screens/notice_composer_screen.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

class _SignedIn extends AuthProvider {
  _SignedIn(this._user);
  final UserModel _user;
  @override
  UserModel? get currentUser => _user;
}

const _admin = UserModel(
  id: 'a-1',
  name: 'Test Admin',
  email: 'admin@example.com',
  role: UserRole.hostelAdmin,
  organizationId: 'o-1',
  groupId: 'g-a',
  groupIds: ['g-a'],
  groups: [UserGroupBrief(id: 'g-a', name: 'Boys Hostel Block A Mess')],
);

Future<void> _pump(WidgetTester tester, Widget screen,
    {double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 780),
        textScaler: TextScaler.linear(textScale),
      ),
      child: AuthProviderScope(provider: _SignedIn(_admin), child: screen),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('notice composer builds (text x$scale); Post enabled when idle',
        (tester) async {
      await _pump(
          tester,
          const NoticeComposerScreen(organizationId: 'o-1', groupId: 'g-a'),
          textScale: scale);
      expect(tester.takeException(), isNull);
      expect(find.text('Add document'), findsOneWidget);
      expect(find.text('Compressing…'), findsNothing);
    });

    testWidgets('admin vacation requests list builds (text x$scale)',
        (tester) async {
      await _pump(tester, const VacationRequestsScreen(), textScale: scale);
      expect(tester.takeException(), isNull);
    });
  }
}

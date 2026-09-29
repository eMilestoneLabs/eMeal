// Issues_Live_Test_16 ISSUE-19/2 — RUNTIME check of the group-scoped vacation
// request form: it must build, lay out at phone width (also at a large text
// scale), and switch groups without any exception. Network reads fail fast
// in the test binding (HTTP 400) — the screen must degrade, never crash.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/student/settings/screens/student_vacation_request_screen.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Signed-in session without a login round trip (test-only subclass).
class _SignedIn extends AuthProvider {
  _SignedIn(this._user);
  final UserModel _user;
  @override
  UserModel? get currentUser => _user;
}

const _user = UserModel(
  id: 'u-1',
  name: 'Test Member',
  email: 'member@example.com',
  role: UserRole.student,
  organizationId: 'o-1',
  groupId: 'g-a',
  groupIds: ['g-a', 'g-b'],
  groups: [
    UserGroupBrief(id: 'g-a', name: 'Boys Hostel Block A Mess'),
    UserGroupBrief(id: 'g-b', name: 'Girls Hostel Night Canteen'),
  ],
);

Future<void> _pump(WidgetTester tester, {double textScale = 1.0}) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp phone
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 780),
        textScaler: TextScaler.linear(textScale),
      ),
      child: AuthProviderScope(
        provider: _SignedIn(_user),
        child: const StudentVacationRequestScreen(organizationId: 'o-1'),
      ),
    ),
  ));
  // Let the (failing) network reads resolve; never wait forever.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('builds at phone width with a group picker for every group',
      (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Request vacation for'), findsOneWidget);
    expect(find.text('Boys Hostel Block A Mess'), findsWidgets);
    expect(find.text('Girls Hostel Night Canteen'), findsWidgets);
  });

  testWidgets('switching the group never throws and keeps both choices',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Girls Hostel Night Canteen').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Boys Hostel Block A Mess').first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Girls Hostel Night Canteen'), findsWidgets);
  });

  testWidgets('no overflow at a large accessibility text scale (1.3x)',
      (tester) async {
    await _pump(tester, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}

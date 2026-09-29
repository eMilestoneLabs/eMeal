// Events switched off — RUNTIME navigation through the REAL app router
// (buildRouter): every way into Events lands on the Coming-soon preview, the
// role screen's Event card opens it, and "Got it" returns. No crash.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/app_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/features/auth/models/auth_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/screens/role_select_screen.dart';
import 'package:smart_meal_management/features/events/screens/events_coming_soon_screen.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Fixed auth state (no storage / network) so only routing is exercised.
class _StubAuth extends AuthProvider {
  _StubAuth({this.user});
  final UserModel? user;
  @override
  AuthState get state => const AuthUnauthenticated();
  @override
  bool get isAuthenticated => user != null;
  @override
  UserModel? get currentUser => user;
}

Future<GoRouter> _boot(WidgetTester tester, AuthProvider auth) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final router = buildRouter(auth);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    AuthProviderScope(
      provider: auth,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  // Screens run looping ambient animations — pump time, never pumpAndSettle.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  const deepLinks = [
    RouteNames.eventEntry,
    RouteNames.eventSignup,
    RouteNames.eventGuestJoin,
    RouteNames.eventAdminRoot,
    RouteNames.eventAdminCreate,
    '/event-admin/event/evt-123',
    '/event-guest?code=ABC123',
  ];

  for (final link in deepLinks) {
    testWidgets('deep link $link opens the Coming-soon preview', (
      tester,
    ) async {
      final router = await _boot(tester, _StubAuth());
      router.go(link);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(EventsComingSoonScreen), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        RouteNames.eventsComingSoon,
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('role screen: Event card shows "Coming soon", opens the preview, '
      '"Got it" returns', (tester) async {
    final router = await _boot(tester, _StubAuth());
    router.go(RouteNames.roleSelect);
    await _settle(tester);
    expect(find.byType(RoleSelectScreen), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('Weddings, parties and functions'), findsOneWidget);

    await tester.tap(find.text('Event'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(EventsComingSoonScreen), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await _settle(tester);
    expect(find.byType(EventsComingSoonScreen), findsNothing);
    expect(find.byType(RoleSelectScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a signed-in EVENT account lands on the preview with Sign out', (
    tester,
  ) async {
    final router = await _boot(
      tester,
      _StubAuth(
        user: const UserModel(
          id: 'e-1',
          name: 'Event Host',
          email: 'host@example.com',
          role: UserRole.eventAdmin,
          organizationId: 'o-1',
        ),
      ),
    );
    router.go(RouteNames.roleSelect); // auth route -> their home -> gate
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(EventsComingSoonScreen), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

// Events module switched off: the router gate sends every Events route to
// the Coming-soon preview, and the preview renders cleanly everywhere.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/app/router/events_gate.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/config/feature_flags.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/events/screens/events_coming_soon_screen.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

class _SignedIn extends AuthProvider {
  _SignedIn(this._user);
  final UserModel _user;
  @override
  UserModel? get currentUser => _user;
}

const _eventRoutes = [
  RouteNames.eventEntry,
  RouteNames.eventSignup,
  RouteNames.eventGuestJoin,
  RouteNames.eventAdminRoot,
  RouteNames.eventAdminCreate,
  '/event-admin/event/abc123',
  RouteNames.eventAdminDashboard,
  RouteNames.eventGuestDashboard,
];

Future<void> _pump(
  WidgetTester tester, {
  AuthProvider? auth,
  double widthDp = 360,
  double textScale = 1.0,
  bool dark = false,
  bool reduceMotion = false,
}) async {
  final heightDp = widthDp * 2.17;
  tester.view.physicalSize = Size(widthDp * 3, heightDp * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  // Mirrors app.dart: AuthProviderScope wraps the whole app, so every
  // pushed route can read it.
  await tester.pumpWidget(
    AuthProviderScope(
      provider: auth ?? AuthProvider(),
      child: MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        // Applied to EVERY route (a MediaQuery above MaterialApp is
        // replaced by the app's own view-based one).
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: reduceMotion,
              ),
              child: child!,
            ),
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const EventsComingSoonScreen(),
                          ),
                        ),
                    child: const Text('open'),
                  ),
                ),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  // Entrance is 1.4 s; the ambient loop repeats, so never pumpAndSettle.
  for (var i = 0; i < 18; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('events gate', () {
    test('Events are switched off by default in this build', () {
      expect(FeatureFlags.eventsEnabled, isFalse);
    });

    test('every Events route opens the preview while switched off', () {
      for (final r in _eventRoutes) {
        expect(
          eventsRedirect(r, enabled: false),
          RouteNames.eventsComingSoon,
          reason: r,
        );
      }
    });

    test('switched on, Events routes work exactly as before', () {
      for (final r in _eventRoutes) {
        expect(eventsRedirect(r, enabled: true), isNull, reason: r);
      }
    });

    test('the preview itself and every other route are never redirected', () {
      for (final r in [
        RouteNames.eventsComingSoon,
        RouteNames.roleSelect,
        RouteNames.login,
        RouteNames.studentDashboard,
        RouteNames.adminDashboard,
        '/notepad',
      ]) {
        expect(eventsRedirect(r, enabled: false), isNull, reason: r);
      }
    });
  });

  group('events preview screen', () {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('renders cleanly at 360 dp (dark=$dark, text x$scale)', (
          tester,
        ) async {
          await _pump(tester, dark: dark, textScale: scale);
          expect(tester.takeException(), isNull);
          expect(find.text('Events are coming'), findsOneWidget);
          expect(find.text('COMING SOON'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }

    testWidgets('lists all six upcoming features', (tester) async {
      await _pump(tester, widthDp: 411);
      for (final title in [
        'Set up in a minute',
        'Guests join by QR',
        'Every plate counted',
        'Your menu, your way',
        'Reports in one tap',
        'Private by design',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(title), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reduced motion shows everything at once, no animation', (
      tester,
    ) async {
      await _pump(tester, reduceMotion: true);
      expect(tester.takeException(), isNull);
      // No entrance animation: content is fully visible at once.
      final fade = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('Events are coming'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade.opacity.value, 1.0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"Got it" returns to the previous screen', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Got it'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('open'), findsOneWidget);
      expect(find.text('Events are coming'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an event account sees "Sign out" (never stuck)', (
      tester,
    ) async {
      await _pump(
        tester,
        auth: _SignedIn(
          const UserModel(
            id: 'e-1',
            name: 'Event Host',
            email: 'host@example.com',
            role: UserRole.eventAdmin,
            organizationId: 'o-1',
          ),
        ),
      );
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Got it'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

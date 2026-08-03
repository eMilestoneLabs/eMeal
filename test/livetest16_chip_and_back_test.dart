import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_theme.dart';
import 'package:smart_meal_management/shared/widgets/shell_back_handler.dart';

/// Live-Test-16 regression guards.
///
/// ISSUE-1 — chip labels were invisible in light mode: `AppTypography.*` states
/// no colour and Flutter resolves the chip label with
/// `chipTheme.labelStyle ?? chipDefaults.labelStyle` (a `??`, NOT a merge —
/// chip.dart:1367), so a colourless theme style discarded the Material-3
/// default that carries the colour and the label reached the engine with no
/// colour at all (rendered white on a near-white chip).
///
/// ISSUE-2 — Android back closed the app from any bottom-nav tab and from any
/// leaf reached with `go`, because a `ShellRoute` tab is a one-page navigator
/// and nothing implemented a back policy.
void main() {
  // ── ISSUE-1: chip label colours ────────────────────────────────────────────

  /// Resolves the colour a chip label actually paints with, exactly as RawChip
  /// hands it to the engine (chip.dart:1450 `DefaultTextStyle`).
  Future<Color?> labelColour(
    WidgetTester tester, {
    required ThemeData theme,
    required Widget chip,
    required String text,
  }) async {
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: Scaffold(body: Center(child: chip))),
    );
    return DefaultTextStyle.of(tester.element(find.text(text))).style.color;
  }

  group('ISSUE-1 chip label contrast', () {
    testWidgets('light: bare unselected chip has a stated colour', (t) async {
      final c = await labelColour(
        t,
        theme: AppTheme.light,
        chip: ChoiceChip(
          label: const Text('Ghugni'),
          selected: false,
          onSelected: (_) {},
        ),
        text: 'Ghugni',
      );
      // Before the fix this was null → engine default (white) on #F1F5F9.
      expect(c, isNotNull, reason: 'a null colour renders white → invisible');
      expect(c, AppColors.textPrimary);
    });

    testWidgets('light: bare SELECTED chip has a stated colour', (t) async {
      // ChoiceChip falls back to chipTheme.secondaryLabelStyle when selected
      // and the call site passed no labelStyle (choice_chip.dart:230).
      final c = await labelColour(
        t,
        theme: AppTheme.light,
        chip: ChoiceChip(
          label: const Text('Alur Dam'),
          selected: true,
          onSelected: (_) {},
        ),
        text: 'Alur Dam',
      );
      expect(c, isNotNull, reason: 'a null colour renders white → invisible');
      expect(c, AppColors.onPrimaryContainer);
    });

    testWidgets('light: bare Chip (no labelStyle at all) has a colour',
        (t) async {
      final c = await labelColour(
        t,
        theme: AppTheme.light,
        chip: const Chip(label: Text('Veg')),
        text: 'Veg',
      );
      expect(c, isNotNull);
    });

    testWidgets('light: a call site that states its own colour still wins',
        (t) async {
      // Guards the already-correct chips (group switcher when selected,
      // correction/vacation filter rows, notepad filters): widget-over-theme
      // merge must not be inverted by the theme fix.
      final c = await labelColour(
        t,
        theme: AppTheme.light,
        chip: ChoiceChip(
          label: const Text('Mine'),
          selected: false,
          onSelected: (_) {},
          labelStyle: const TextStyle(color: AppColors.error),
        ),
        text: 'Mine',
      );
      expect(c, AppColors.error);
    });

    testWidgets('light: a null colour on a call site now inherits the theme',
        (t) async {
      // The student group switcher passes `color: selected ? primary : null`.
      final c = await labelColour(
        t,
        theme: AppTheme.light,
        chip: ChoiceChip(
          label: const Text('Midnapore Namaste'),
          selected: false,
          onSelected: (_) {},
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        text: 'Midnapore Namaste',
      );
      expect(c, AppColors.textPrimary);
    });

    testWidgets('dark theme is unchanged', (t) async {
      final c = await labelColour(
        t,
        theme: AppTheme.dark,
        chip: ChoiceChip(
          label: const Text('Ghugni'),
          selected: false,
          onSelected: (_) {},
        ),
        text: 'Ghugni',
      );
      expect(c, AppColors.textPrimaryDark);
    });
  });

  // ── ISSUE-2: home detection (the shells' own wiring) ───────────────────────

  group('ISSUE-2 isShellHomeLocation', () {
    test('the home tab is home', () {
      expect(
          isShellHomeLocation(
              RouteNames.studentDashboard, RouteNames.studentDashboard),
          isTrue);
      expect(
          isShellHomeLocation(
              RouteNames.adminDashboard, RouteNames.adminDashboard),
          isTrue);
    });

    test('a query string still resolves to home', () {
      expect(
          isShellHomeLocation(
              '${RouteNames.studentDashboard}?ref=push',
              RouteNames.studentDashboard),
          isTrue);
    });

    test('NON-TAB leaves are NOT home', () {
      // The trap: these all report bottom-nav index 0 via _indexFromLocation,
      // so an index-based policy would exit the app here.
      for (final leaf in [
        RouteNames.studentSettings,
        RouteNames.studentBilling,
        RouteNames.studentAttendanceHistory,
        RouteNames.notepad,
      ]) {
        expect(isShellHomeLocation(leaf, RouteNames.studentDashboard), isFalse,
            reason: '$leaf must never be mistaken for Home');
      }
      for (final leaf in [
        RouteNames.adminSettings,
        RouteNames.adminProfile,
        RouteNames.adminExports,
        RouteNames.adminMyAttendance,
      ]) {
        expect(isShellHomeLocation(leaf, RouteNames.adminDashboard), isFalse,
            reason: '$leaf must never be mistaken for Home');
      }
    });

    test('other tabs are NOT home', () {
      for (final tab in [
        RouteNames.studentMeals,
        RouteNames.studentAttendance,
        RouteNames.studentWeeklyMenu,
        RouteNames.studentProfile,
      ]) {
        expect(isShellHomeLocation(tab, RouteNames.studentDashboard), isFalse);
      }
    });

    test('a sub-route of home is NOT home (exact match, never startsWith)', () {
      expect(
          isShellHomeLocation(
              '${RouteNames.studentDashboard}/detail',
              RouteNames.studentDashboard),
          isFalse);
    });

    test('the two shells cannot be confused for each other', () {
      expect(
          isShellHomeLocation(
              RouteNames.adminDashboard, RouteNames.studentDashboard),
          isFalse);
      expect(
          isShellHomeLocation(
              RouteNames.studentDashboard, RouteNames.adminDashboard),
          isFalse);
    });
  });

  // ── ISSUE-2: shell back policy ─────────────────────────────────────────────

  group('ISSUE-2 ShellBackHandler', () {
    const home = '/student/dashboard';
    late List<String> exitCalls;
    late List<bool> backOwnership;

    setUp(() {
      exitCalls = [];
      backOwnership = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.pop') exitCalls.add(call.method);
        // What the framework tells Android about who handles back. On Android
        // 13+ (`enableOnBackInvokedCallback=true` in the manifest) a `false`
        // here means the system finishes the Activity ITSELF and the back
        // policy never runs — the exact defect seen on device.
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          backOwnership.add(call.arguments as bool);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    /// Replicates the production topology: a ShellRoute whose tabs are switched
    /// with `go` (one-page navigator), wrapped in the real ShellBackHandler.
    /// `/student/settings` is included as a NON-TAB leaf — the case that
    /// `_indexFromLocation` maps to index 0 and that an index-based back policy
    /// would have mistaken for Home.
    (GoRouter, List<String>) buildRouter() {
      final goHomeCalls = <String>[];
      late final GoRouter router;
      String location() =>
          router.routerDelegate.currentConfiguration.uri.toString();

      router = GoRouter(
        initialLocation: home,
        routes: [
          ShellRoute(
            navigatorKey: GlobalKey<NavigatorState>(debugLabel: 'student'),
            builder: (c, s, child) => ShellBackHandler(
              // The REAL production predicate, so this exercises the exact
              // home-detection the shells use.
              isHome: () => isShellHomeLocation(location(), home),
              onGoHome: () {
                goHomeCalls.add('home');
                router.go(home);
              },
              child: Scaffold(body: child),
            ),
            routes: [
              GoRoute(path: home, builder: (c, s) => const Text('dashboard')),
              GoRoute(
                  path: '/student/meals',
                  builder: (c, s) => const Text('meals')),
              GoRoute(
                  path: '/student/settings',
                  builder: (c, s) => const Text('settings')),
              GoRoute(
                path: '/student/attendance',
                builder: (c, s) => const Text('attendance'),
                routes: [
                  GoRoute(
                      path: 'history',
                      builder: (c, s) => const Text('history')),
                ],
              ),
            ],
          ),
        ],
      );
      return (router, goHomeCalls);
    }

    Future<(GoRouter, List<String>)> pumpShell(WidgetTester t) async {
      final (router, goHomeCalls) = buildRouter();
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.pumpAndSettle();
      return (router, goHomeCalls);
    }

    testWidgets(
        'ANDROID GATE: framework claims back on a tab (setFrameworkHandlesBack)',
        (t) async {
      // THE decisive check, and the one my other tests were blind to.
      //
      // The manifest sets `android:enableOnBackInvokedCallback="true"`, so on
      // Android 13+ the system only routes back into Flutter when the
      // framework has said it wants it, via
      // `SystemNavigator.setFrameworkHandlesBack(true)`
      // (WidgetsApp._defaultOnNavigationNotification → app.dart:1450).
      // That flag is `navigatorCanPop || routeBlocksPop` (navigator.dart:3734).
      // On a tab route BOTH navigators have one page, so `navigatorCanPop` is
      // false — the flag is true ONLY because our PopScope makes the root
      // page report `doNotPop`.
      //
      // If this is ever false, Android finishes the Activity itself and
      // `popRoute()` is NEVER called: the app closes and every other test in
      // this file still passes, because they invoke `popRoute()` directly.
      final handled = backOwnership;
      final (router, _) = await pumpShell(t);
      // WidgetsApp._defaultOnNavigationNotification returns EARLY while
      // `_appLifecycleState` is null (app.dart:1442-1445) — the default in a
      // widget test. Without this the platform is never told anything and the
      // assertions below would report a false alarm.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();

      router.go('/student/meals');
      await t.pumpAndSettle();
      expect(handled.isNotEmpty, isTrue,
          reason: 'the framework never told Android who handles back');
      expect(handled.last, isTrue,
          reason: 'on a non-Home TAB the framework must claim back, or Android '
              'finishes the Activity and back never reaches ShellBackHandler');

      router.go(home);
      await t.pumpAndSettle();
      expect(handled.last, isTrue,
          reason: 'on HOME the shell must still claim back, or Android closes '
              'the app before the exit-confirmation can ever run');

      router.push('/student/settings');
      await t.pumpAndSettle();
      expect(handled.last, isTrue, reason: 'a pushed route is poppable');
    });

    testWidgets('back from a bottom-nav tab returns Home, does NOT exit',
        (t) async {
      final (router, goHomeCalls) = await pumpShell(t);
      router.go('/student/meals');
      await t.pumpAndSettle();

      final handled = await router.routerDelegate.popRoute();
      await t.pumpAndSettle();

      expect(handled, isTrue, reason: 'false → framework fires SystemNavigator');
      expect(exitCalls, isEmpty);
      expect(goHomeCalls, ['home']);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), home);
    });

    testWidgets('back from a go-reached NON-TAB leaf returns Home, does NOT exit',
        (t) async {
      // The trap: /student/settings maps to bottom-nav index 0, so a policy
      // keyed off the tab index would read "we are on Home" and exit here.
      final (router, goHomeCalls) = await pumpShell(t);
      router.go('/student/settings');
      await t.pumpAndSettle();

      final handled = await router.routerDelegate.popRoute();
      await t.pumpAndSettle();

      expect(handled, isTrue);
      expect(exitCalls, isEmpty);
      expect(goHomeCalls, ['home']);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), home);
    });

    testWidgets('on Home: first back hints, second back exits', (t) async {
      final (router, goHomeCalls) = await pumpShell(t);

      final first = await router.routerDelegate.popRoute();
      await t.pump();
      expect(first, isTrue);
      expect(exitCalls, isEmpty, reason: 'a single back must never exit');
      expect(goHomeCalls, isEmpty, reason: 'already home — no navigation');
      expect(find.text('Press back again to exit'), findsOneWidget);

      final second = await router.routerDelegate.popRoute();
      await t.pump();
      expect(second, isTrue);
      expect(exitCalls, ['SystemNavigator.pop']);
    });

    testWidgets('on Home: a back press AFTER the window only hints again',
        (t) async {
      final (router, _) = await pumpShell(t);

      await router.routerDelegate.popRoute();
      await t.pump();
      expect(exitCalls, isEmpty);

      // Let the confirm window lapse (plus the snackbar it is tied to).
      await t.pump(AppConstants.backExitConfirmWindow + const Duration(seconds: 1));
      await t.pumpAndSettle();

      await router.routerDelegate.popRoute();
      await t.pump();
      expect(exitCalls, isEmpty, reason: 'expired confirmation must not exit');
      expect(find.text('Press back again to exit'), findsOneWidget);
    });

    testWidgets('a pending exit confirmation is DROPPED when we leave Home',
        (t) async {
      // Without the `_lastBackAt = null` reset this exits the app: the stale
      // Home timestamp is still inside the window when we arrive back at Home,
      // so the very next back press would be read as the CONFIRMING second tap.
      final (router, goHomeCalls) = await pumpShell(t);

      await router.routerDelegate.popRoute(); // 1st back on Home → hint
      await t.pump();
      expect(exitCalls, isEmpty);

      router.go('/student/meals'); // leave Home well inside the window
      await t.pumpAndSettle();

      await router.routerDelegate.popRoute(); // back → Home (resets)
      await t.pumpAndSettle();
      expect(goHomeCalls, ['home']);
      expect(exitCalls, isEmpty);

      await router.routerDelegate.popRoute(); // must HINT, not exit
      await t.pump();
      expect(exitCalls, isEmpty,
          reason: 'a stale confirmation must never close the app');
      expect(find.text('Press back again to exit'), findsOneWidget);
    });

    testWidgets('a PUSHED route still pops normally — handler not consulted',
        (t) async {
      final (router, goHomeCalls) = await pumpShell(t);
      router.push('/student/settings');
      await t.pumpAndSettle();

      final handled = await router.routerDelegate.popRoute();
      await t.pumpAndSettle();

      expect(handled, isTrue);
      expect(exitCalls, isEmpty);
      expect(goHomeCalls, isEmpty,
          reason: 'the shell navigator could pop, so the policy must not run');
      expect(router.routerDelegate.currentConfiguration.uri.toString(), home);
    });

    testWidgets('a pushed CHILD route pops back to its pusher', (t) async {
      final (router, goHomeCalls) = await pumpShell(t);
      router.push('/student/attendance/history');
      await t.pumpAndSettle();

      await router.routerDelegate.popRoute();
      await t.pumpAndSettle();

      expect(goHomeCalls, isEmpty);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), home);
    });

    testWidgets('NO NAVIGATION CRASH — long mixed sequence throws nothing',
        (t) async {
      // Hammers every combination the back policy can meet: tab switches,
      // pushed leaves, pushed child routes, repeated backs at every depth, and
      // back pressed twice at the root. Asserts the app never throws and never
      // exits except on a genuine confirmed double-back at Home.
      final (router, _) = await pumpShell(t);
      // Without a lifecycle state WidgetsApp never talks to the platform
      // (app.dart:1442-1445), so back-ownership could not be observed.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      String loc() => router.routerDelegate.currentConfiguration.uri.toString();

      /// Back ownership must NEVER be surrendered while a shell is on screen.
      /// A single `false` at any point means Android takes over and closes the
      /// app instead of running the policy — the device-only defect.
      void ownsBack(String step) {
        expect(backOwnership.isEmpty || backOwnership.last, isTrue,
            reason: 'back ownership LOST after $step — Android would close '
                'the app here instead of calling ShellBackHandler');
      }

      // Disarms any pending exit confirmation, so no step below is ever a
      // CONFIRMED double-back at Home. Two backs at Home inside the window are
      // supposed to exit — that path is covered by its own test above; here we
      // are proving the sequences that must NOT exit, never do.
      Future<void> lapseWindow() async {
        await t.pump(
            AppConstants.backExitConfirmWindow + const Duration(seconds: 1));
        await t.pumpAndSettle();
      }

      const tabs = ['/student/meals', '/student/attendance', home];
      const leaves = ['/student/settings', '/student/attendance/history'];

      for (var round = 0; round < 3; round++) {
        for (final tab in tabs) {
          router.go(tab);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'go($tab) threw');
          ownsBack('go($tab)');

          for (final leaf in leaves) {
            router.push(leaf);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: 'push($leaf) threw');
            ownsBack('push($leaf)');

            await router.routerDelegate.popRoute(); // pop the leaf
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: 'pop of $leaf threw');
            ownsBack('pop($leaf)');
          }

          // Back with nothing left to pop → policy runs.
          await router.routerDelegate.popRoute();
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'policy back threw');
          ownsBack('policy back from $tab');
          await lapseWindow();
        }

        // Nested pushes, unwound exactly, then one policy back.
        router.push(leaves[0]);
        router.push(leaves[1]);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'nested push threw');

        for (var i = 0; i < 3; i++) {
          await router.routerDelegate.popRoute();
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'unwind step $i threw');
        }
        await lapseWindow();

        expect(exitCalls, isEmpty,
            reason: 'round $round contained no confirmed double-back, so the '
                'app must still be running');
      }

      // The app is still alive and coherent on a real route.
      expect(loc(), home);
      expect(t.takeException(), isNull);
    });

    testWidgets('the wrapper does NOT remount its subtree on rebuild',
        (t) async {
      // The only mechanism by which adding ShellBackHandler at the TOP of a
      // shell's tree could make an unrelated screen "always load": if the
      // wrapper caused the subtree to remount, every screen's initState /
      // didChangeDependencies would re-run on each shell rebuild and refetch.
      // This pins that it does not — child State survives parent rebuilds.
      var buildCount = 0;
      late StateSetter rebuildParent;

      await t.pumpWidget(MaterialApp(
        home: StatefulBuilder(builder: (ctx, setState) {
          rebuildParent = setState;
          buildCount++;
          return ShellBackHandler(
            isHome: () => true,
            onGoHome: () {},
            child: const _StatefulProbe(),
          );
        }),
      ));
      await t.pumpAndSettle();

      final first = t.state<_StatefulProbeState>(find.byType(_StatefulProbe));
      expect(first.initCount, 1);
      expect(buildCount, 1);

      for (var i = 0; i < 5; i++) {
        rebuildParent(() {});
        await t.pumpAndSettle();
      }

      final after = t.state<_StatefulProbeState>(find.byType(_StatefulProbe));
      expect(identical(first, after), isTrue,
          reason: 'subtree was REMOUNTED — every screen would refetch on each '
              'shell rebuild');
      expect(after.initCount, 1,
          reason: 'initState re-ran → screens would reload repeatedly');
      expect(buildCount, 6, reason: 'the parent did rebuild, so this is a real '
          'test of reconciliation, not a no-op');
    });

    testWidgets('NO CRASH: back mashed MID-TRANSITION (never settled)',
        (t) async {
      // Every other test in this file settles between steps, so none of them
      // ever exercises a back press while a route transition is still
      // animating — which is exactly what a real user does when the app feels
      // slow. Here nothing is settled: pushes are interrupted, and two back
      // presses are fired concurrently on a half-built stack.
      final (router, _) = await pumpShell(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        router.push('/student/settings');
        await t.pump(const Duration(milliseconds: 16)); // one frame in
        router.push('/student/attendance/history');
        await t.pump(const Duration(milliseconds: 16)); // still animating

        // Two concurrent backs on a stack that is mid-flight.
        unawaited(router.routerDelegate.popRoute());
        unawaited(router.routerDelegate.popRoute());
        await t.pump(const Duration(milliseconds: 16));
        expect(t.takeException(), isNull,
            reason: 'concurrent mid-transition back threw at iteration $i');

        // A tab switch landing on top of an unfinished pop.
        router.go('/student/meals');
        await t.pump(const Duration(milliseconds: 16));
        unawaited(router.routerDelegate.popRoute());
        await t.pump(const Duration(milliseconds: 16));
        expect(t.takeException(), isNull,
            reason: 'back during an unsettled tab switch threw at $i');
      }

      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'settling revealed a late error');
      // The app must still be alive and on a real route.
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        anyOf(home, '/student/meals', '/student/settings',
            '/student/attendance/history'),
      );
    });

    testWidgets('an open DIALOG pops FIRST — the root-navigator path',
        (t) async {
      // Distinct code path from the bottom-sheet test below, and it was
      // untested until now: `showDialog` defaults to `useRootNavigator: TRUE`
      // (dialog.dart:1491) so a dialog lands on the ROOT navigator, ABOVE the
      // shell page. `_findCurrentNavigator` then sees the shell route is no
      // longer `isCurrent` and stops its descent (delegate.dart:110), so the
      // ROOT navigator pops the dialog. `showModalBottomSheet` defaults to
      // FALSE (bottom_sheet.dart:1255) and lands on the SHELL navigator, which
      // is reached by the opposite branch — the descent-because-canPop one.
      final (router, goHomeCalls) = await pumpShell(t);
      showDialog<void>(
        context: t.element(find.text('dashboard')),
        builder: (_) => const AlertDialog(content: Text('dlg')),
      );
      await t.pumpAndSettle();
      expect(find.text('dlg'), findsOneWidget);

      await router.routerDelegate.popRoute();
      await t.pumpAndSettle();

      expect(find.text('dlg'), findsNothing, reason: 'the dialog must close');
      expect(exitCalls, isEmpty, reason: 'a dialog back must never exit');
      expect(goHomeCalls, isEmpty, reason: 'the policy must not run');
      expect(t.takeException(), isNull);
    });

    testWidgets('an open modal sheet pops FIRST — policy not consulted',
        (t) async {
      // Guards the correction / guest sheets and their own PopScopes: a sheet
      // makes the shell route non-current, which stops go_router's descent at
      // the root navigator so the sheet is what pops.
      final (router, goHomeCalls) = await pumpShell(t);
      showModalBottomSheet<void>(
        context: t.element(find.text('dashboard')),
        builder: (_) => const SizedBox(height: 120, child: Text('sheet')),
      );
      await t.pumpAndSettle();
      expect(find.text('sheet'), findsOneWidget);

      await router.routerDelegate.popRoute();
      await t.pumpAndSettle();

      expect(find.text('sheet'), findsNothing, reason: 'the sheet must close');
      expect(exitCalls, isEmpty);
      expect(goHomeCalls, isEmpty);
    });
  });
}

/// Probe for the remount test: counts how many times initState runs.
class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe();
  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  int initCount = 0;
  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

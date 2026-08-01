import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/app/router/route_kinds.dart';
import 'package:smart_meal_management/app/router/route_names.dart';

/// Live-Test-16 — static guard for the navigation defect class.
///
/// The bug was NOT that navigation is decentralised (that is the go_router
/// idiom and is correct). It was that route KIND was implicit: nothing recorded
/// that `/student/settings` is a leaf and `/student/meals` is a tab, so each
/// call site guessed, and two guessed wrong — `go` on a leaf replaces the
/// shell's only page, leaving no back arrow and closing the app on back.
///
/// `kRouteKinds` is now that record. This suite keeps it honest by scanning the
/// real source, so a NEW `go`-to-a-leaf fails here instead of on a device.
void main() {
  final libDir = Directory('lib');

  /// Every `.dart` file under lib/, with `//` line comments stripped so a
  /// documentation example can never be mistaken for a call site.
  late final List<(String, String)> sources = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => (
            f.path.replaceAll(r'\', '/'),
            f
                .readAsStringSync()
                .split('\n')
                .map((l) => l.trimLeft().startsWith('//') ? '' : l)
                .join('\n'),
          ))
      .toList();

  /// `RouteNames` constant name → path, parsed from the source so this test
  /// never duplicates the constants (and cannot go stale when they change).
  late final Map<String, String> nameToPath = {
    for (final m in RegExp(r"static const String (\w+) = '([^']+)';")
        .allMatches(File('lib/app/router/route_names.dart').readAsStringSync()))
      m.group(1)!: m.group(2)!,
  };

  test('the scan actually scanned something (false-green self-check)', () {
    // Without this, a wrong working directory would leave `sources` empty and
    // the leaf guard below would pass vacuously — the worst kind of green.
    expect(nameToPath.length, greaterThan(20));
    expect(nameToPath['studentSettings'], RouteNames.studentSettings);
    expect(nameToPath['studentDashboard'], RouteNames.studentDashboard);
    expect(sources.length, greaterThan(100), reason: 'lib/ was not scanned');
    expect(
      sources.any((s) => s.$1.endsWith('lib/features/student/student_shell.dart')),
      isTrue,
      reason: 'the scan must reach the shells, where the defect lived',
    );
  });

  test('every classified path is a real RouteNames value (no typos)', () {
    final valid = nameToPath.values.toSet();
    for (final path in kRouteKinds.keys) {
      expect(valid, contains(path),
          reason: '$path is classified but is not a RouteNames constant');
    }
  });

  test('deep-link behaviour did NOT drift when the list moved', () {
    // Pinned: exactly the paths `notification_route_resolver._knownRoutes`
    // accepted before `kRouteKinds` replaced it. Changing this set changes what
    // a push notification is allowed to open — do so deliberately.
    const before = {
      '/', '/role-select',
      '/student/dashboard', '/student/meals', '/student/attendance',
      '/student/attendance/history', '/student/menu', '/student/profile',
      '/student/settings', '/student/billing',
      '/admin/dashboard', '/admin/meals', '/admin/meals/schedule',
      '/admin/attendance', '/admin/groups', '/admin/exports', '/admin/billing',
      '/admin/settings', '/admin/profile', '/admin/more', '/admin/my-attendance',
      '/groups/join', '/notepad',
      '/event-admin', '/event-admin/create', '/event-admin/dashboard',
      '/event-guest/join', '/event-guest',
    };
    expect(kRouteKinds.keys.toSet(), before);
    expect(kRouteKindPrefixes, ['/admin/groups/', '/event-admin/event/']);
  });

  test('registered/unregistered matching is unchanged, query intents included',
      () {
    expect(isRegisteredRoute(RouteNames.studentBilling), isTrue);
    expect(isRegisteredRoute('/admin/attendance?open=corrections'), isTrue);
    expect(isRegisteredRoute('/admin/groups/abc123'), isTrue);
    expect(isRegisteredRoute('/event-admin/event/e1'), isTrue);
    expect(isRegisteredRoute('/nope'), isFalse);
    // Auth routes must NOT be notification-addressable.
    expect(isRegisteredRoute(RouteNames.login), isFalse);
    expect(isRegisteredRoute(RouteNames.otp), isFalse);
  });

  test('routeKindOf resolves exact paths and dynamic families', () {
    expect(routeKindOf(RouteNames.studentSettings), RouteKind.leaf);
    expect(routeKindOf(RouteNames.studentMeals), RouteKind.tab);
    expect(routeKindOf(RouteNames.roleSelect), RouteKind.reset);
    expect(routeKindOf('/student/dashboard?ref=x'), RouteKind.tab);
    expect(routeKindOf('/admin/groups/g1'), RouteKind.leaf);
    expect(routeKindOf('/unknown'), isNull);
  });

  test('NO leaf route is entered with `go` anywhere in lib/', () {
    // The defect class. `go` on a leaf leaves the shell navigator with a single
    // page: no back arrow, and Android back closes the app.
    //
    // Deliberately one-directional — `push`ing a TAB is safe and is done on
    // purpose (the admin dashboard's quick actions drill into Groups / Meals /
    // Attendance), because a push always leaves something to pop.
    final pattern =
        RegExp(r'\b(?:context|router|_router|GoRouter\.of\(context\))\s*'
            r'\.go\(\s*RouteNames\.(\w+)');
    final violations = <String>[];

    for (final (path, src) in sources) {
      for (final m in pattern.allMatches(src)) {
        final name = m.group(1)!;
        final route = nameToPath[name];
        if (route == null) continue;
        if (routeKindOf(route) == RouteKind.leaf) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          violations.add('$path:$line  go(RouteNames.$name)  → $route');
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'Leaf routes must be entered with context.push(...), not '
            'context.go(...) — `go` replaces the shell page, so the screen '
            'renders with no back arrow and Android back exits the app:\n'
            '${violations.join('\n')}');
  });

  test('every shell tab route is classified as a tab', () {
    // Guards the inverse mistake: mis-labelling a real tab as a leaf would make
    // ShellBackHandler treat a tab switch as a drill-down.
    for (final tab in [
      RouteNames.studentDashboard,
      RouteNames.studentMeals,
      RouteNames.studentAttendance,
      RouteNames.studentWeeklyMenu,
      RouteNames.studentProfile,
      RouteNames.adminDashboard,
      RouteNames.adminGroups,
      RouteNames.adminMealConfig,
      RouteNames.adminAttendance,
      RouteNames.adminMore,
    ]) {
      expect(routeKindOf(tab), RouteKind.tab, reason: '$tab is a bottom-nav tab');
    }
  });
}

// A group may not carry the ORGANISATION's own name.
//
// Runtime-validated, not compile-validated: the create form is pumped for real
// and the inline error is read off the rendered TextField.
//
// Also pins the crash-safety of the lookup. AdminGroupsScreen is reachable BOTH
// as a shell tab (scope present) and as a plain MaterialPageRoute from the
// notice feed (scope absent). `AdminDashboardScope.of` asserts then force-
// unwraps — in a RELEASE build the assert is stripped and that is a null-check
// crash — so the screen must use `maybeOf`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';

void main() {
  group('scope lookup must be crash-safe outside the admin shell', () {
    testWidgets('maybeOf returns null with NO scope above it', (tester) async {
      AdminDashboardProvider? seen;
      var built = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              // Exactly the notice-feed situation: no AdminDashboardScope.
              seen = AdminDashboardScope.maybeOf(context);
              built = true;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(tester.takeException(), isNull,
          reason: 'must not throw where the scope is absent');
      expect(built, isTrue);
      expect(seen, isNull);
    });

    testWidgets('maybeOf finds the provider when the scope IS present',
        (tester) async {
      final provider = AdminDashboardProvider();
      AdminDashboardProvider? seen;

      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardScope(
            notifier: provider,
            child: Builder(
              builder: (context) {
                seen = AdminDashboardScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(seen, same(provider),
          reason: 'guards against a vacuous test — it must really resolve');
      expect(seen!.orgName, AdminDashboardProvider.kOrgNamePlaceholder);
    });
  });
}

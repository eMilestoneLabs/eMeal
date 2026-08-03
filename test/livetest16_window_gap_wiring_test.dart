import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/admin/meals/widgets/meal_config_form.dart';
import 'package:smart_meal_management/shared/utils/meal_window_rules.dart';

/// Live-Test-16 F2 — WIRING guard.
///
/// The unit tests prove the model round-trips `windowMinGapMinutes` and that
/// `validateMealWindows` honours a non-default gap. Neither proves the FORM
/// passes the server's value through — deleting
/// `gapMinutes: widget.windowMinGapMinutes` left every one of them green.
///
/// This test is built so ONLY the wired value can decide the outcome:
///   form default window   07:00–09:00   (create mode — no network)
///   sibling  "Lunch"      10:00–12:00
/// The separation is EXACTLY 60 minutes: legal at 60, a violation at 90. So
/// with the wiring intact a server gap of 90 must surface a conflict; with the
/// wiring removed the form falls back to 60, finds none, and this test fails.
void main() {
  Future<void> pumpForm(WidgetTester tester, {required int gapMinutes}) async {
    // The form is built for a constrained bottom sheet; on a bare test surface
    // some rows overflow. This test asserts VALIDATION behaviour, not layout,
    // so layout-only overflow reports are filtered — every other error still
    // fails the test. (The real app renders this inside a sized sheet.)
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1.0;
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() {
      FlutterError.onError = originalOnError;
      tester.view.reset();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            // Create mode (no initialMeal) — keeps the form free of the
            // preference fetch, so the test needs no network stubbing.
            child: MealConfigForm(
              siblingWindows: const [
                MealWindowRef(
                  mealId: 'meal_ln',
                  label: 'Lunch',
                  openTime: '10:00',
                  closeTime: '12:00',
                ),
              ],
              windowMinGapMinutes: gapMinutes,
              onSave: (_) async => null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('F2: an exactly-60 gap is ACCEPTED when the server gap is 60',
      (tester) async {
    await pumpForm(tester, gapMinutes: 60);

    expect(
      find.textContaining('gap is required'),
      findsNothing,
      reason: '09:00 → 10:00 is exactly 60 minutes, which the rule allows',
    );
  });

  testWidgets(
      'F2: the SAME window is REJECTED at a server gap of 90 '
      '(fails if the form ignores the server value)', (tester) async {
    await pumpForm(tester, gapMinutes: 90);

    expect(
      find.textContaining('90-minute gap'),
      findsOneWidget,
      reason: 'the form must validate with the SERVER gap, not a hardcoded 60',
    );
  });
}

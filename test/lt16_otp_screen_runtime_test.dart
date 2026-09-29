// Issues_Live_Test_16 ISSUE-3 — RUNTIME check of the signup OTP screen:
// Resend is live immediately (no 60 s lock) with the longer label, and the
// screen lays out at phone width and a large text scale without overflow.
// Event signup and "Verify now" keep their countdown (zero impact).
//
// Widths: 411 dp (common phone) and 360 dp (budget phones). At 360 dp the OTP
// row (6 x 46 px + 5 x 10 px = 326 px > 312 px) used to clip the last box by
// 14 px (present since the MVP); it now scales down to fit.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/screens/otp_screen.dart';

Future<void> _pump(WidgetTester tester, Widget screen,
    {double textScale = 1.0, double widthDp = 411}) async {
  final heightDp = widthDp * 2.17;
  tester.view.physicalSize = Size(widthDp * 3, heightDp * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(widthDp, heightDp),
        textScaler: TextScaler.linear(textScale),
      ),
      child: AuthProviderScope(provider: AuthProvider(), child: screen),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  const signup = OtpScreen(
    identifier: 'member@example.com',
    roleContext: 'student',
    isSignup: true,
    purpose: 'signup',
  );

  testWidgets('student signup: Resend is offered at once with the clear label',
      (tester) async {
    await _pump(tester, signup);
    expect(tester.takeException(), isNull);
    expect(find.text("Didn't get the code? Resend OTP"), findsOneWidget);
    // Unmount so the screen's own timers are cancelled cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signup screen has no NEW overflow at 1.3x text', (tester) async {
    await _pump(tester, signup, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('360 dp phone (text x$scale): all 6 OTP boxes fit, no overflow',
        (tester) async {
      await _pump(tester, signup, widthDp: 360, textScale: scale);
      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNWidgets(6));
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('360 dp: typing into every box still works after scaling',
      (tester) async {
    await _pump(tester, signup, widthDp: 360);
    final boxes = find.byType(TextField);
    for (var i = 0; i < 6; i++) {
      await tester.tap(boxes.at(i));
      await tester.enterText(boxes.at(i), '${i + 1}');
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 6; i++) {
      expect(
          tester.widget<TextField>(boxes.at(i)).controller?.text, '${i + 1}');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('event signup is untouched: keeps the countdown, no new label',
      (tester) async {
    await _pump(
        tester,
        const OtpScreen(
          identifier: 'guest@example.com',
          roleContext: 'event',
          isSignup: true,
          purpose: 'signup',
        ));
    expect(tester.takeException(), isNull);
    expect(find.text("Didn't get the code? Resend OTP"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Verify now" (popOnSuccess) is untouched: keeps the countdown',
      (tester) async {
    await _pump(
        tester,
        const OtpScreen(
          identifier: 'member@example.com',
          roleContext: 'student',
          isSignup: true,
          purpose: 'signup',
          popOnSuccess: true,
        ));
    expect(tester.takeException(), isNull);
    expect(find.text("Didn't get the code? Resend OTP"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

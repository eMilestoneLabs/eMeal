import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/errors/failure.dart';

/// SRS Module 03 ACC-005 (survey Q1/Q19) — client side of the participation
/// gate: when the server rejects a participation write with
/// EMAIL_VERIFICATION_REQUIRED, the app shows a guided "Verify your email"
/// flow that requests a fresh OTP immediately (same flow as the profile
/// badge) instead of a dead-end error snackbar.
class VerificationGate {
  VerificationGate._();

  /// Matches the backend EmailVerifiedGuard message contract.
  static bool isVerificationRequired(Failure f) =>
      messageRequiresVerification(f.message);

  /// Message-based variant for providers that surface plain error strings.
  static bool messageRequiresVerification(String? message) =>
      (message ?? '').toLowerCase().contains('verify your email');

  /// Returns true when the failure was the verification gate AND the guided
  /// dialog was shown — callers skip their default error snackbar then.
  static Future<bool> handle(
    BuildContext context,
    Failure failure, {
    required String email,
    String roleContext = 'student',
  }) =>
      handleMessage(
        context,
        failure.message,
        email: email,
        roleContext: roleContext,
      );

  /// Same as [handle] for plain error strings (provider `actionError` etc.).
  static Future<bool> handleMessage(
    BuildContext context,
    String? message, {
    required String email,
    String roleContext = 'student',
  }) async {
    if (!messageRequiresVerification(message)) return false;
    if (!context.mounted) return true;

    final verifyNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify your email'),
        content: const Text(
          'Email verification is required before you can mark attendance, '
          'book guests, or send requests. Verify now to continue — we will '
          'send a code to your email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verify now'),
          ),
        ],
      ),
    );

    if (verifyNow == true && context.mounted && email.trim().isNotEmpty) {
      context.push(
        RouteNames.otp,
        extra: OtpRouteExtra(
          identifier: email.trim(),
          roleContext: roleContext,
          purpose: 'signup',
          isSignup: true,
          autoRequest: true, // send a fresh verification code on entry
          popOnSuccess: true,
        ),
      );
    }
    return true;
  }
}

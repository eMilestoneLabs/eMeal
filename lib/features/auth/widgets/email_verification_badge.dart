import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_extras.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';

/// Email verification status chip (SRS AUTH-036/040/041).
///
/// Three render modes:
///  - **Own profile** (`interactive: true`): green "Verified" pill, or an amber
///    "Unverified · Verify now" pill that opens the OTP screen and stamps the
///    account verified on success.
///  - **Member lists** (`interactive: false`): a read-only badge that simply
///    reflects another user's status — the viewer can't verify on their behalf.
///  - **Inline** (`iconOnly: true`): a tiny tinted dot+icon (with tooltip) to sit
///    next to a name in dense rows.
class EmailVerificationBadge extends StatelessWidget {
  const EmailVerificationBadge({
    super.key,
    required this.verified,
    this.email = '',
    this.roleContext = 'student',
    this.compact = false,
    this.interactive = true,
    this.iconOnly = false,
  });

  final bool verified;

  /// Account email — required only when [interactive] and unverified (the code
  /// is delivered to email). Ignored in read-only / icon modes.
  final String email;
  final String roleContext;

  /// Hides the "Verify now" caption (smaller pill).
  final bool compact;

  /// When true, an unverified badge is tappable and opens the OTP flow.
  /// Set false for other people's status (e.g. a member directory).
  final bool interactive;

  /// Renders a minimal icon-only indicator for inline use after a name.
  final bool iconOnly;

  static const _green = Color(0xFF16A34A);
  static const _amber = Color(0xFFD97706);

  bool get _canVerify => interactive && !verified && email.trim().isNotEmpty;

  void _startVerification(BuildContext context) {
    context.push(
      RouteNames.otp,
      extra: OtpRouteExtra(
        identifier: email.trim(),
        roleContext: roleContext,
        purpose: 'signup',
        isSignup: true,
        autoRequest: true, // request a fresh verification code on entry
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = verified ? _green : _amber;
    final icon = verified ? Icons.verified_rounded : Icons.error_outline_rounded;
    final tip = verified ? 'Email verified' : 'Email not verified';

    // ── Inline icon-only (member rows) ──────────────────────────────────────
    if (iconOnly) {
      return Tooltip(
        message: tip,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.40)),
          ),
          child: Icon(icon, size: 11, color: color),
        ),
      );
    }

    // ── Pill ────────────────────────────────────────────────────────────────
    final pill = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            verified ? 'Verified' : 'Unverified',
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_canVerify && !compact) ...[
            const SizedBox(width: 6),
            Container(width: 1, height: 12, color: color.withValues(alpha: 0.35)),
            const SizedBox(width: 6),
            Text(
              'Verify now',
              style: AppTypography.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: color,
              ),
            ),
          ],
        ],
      ),
    );

    if (!_canVerify) return Semantics(label: tip, child: pill);

    return Semantics(
      button: true,
      label: 'Email not verified. Tap to verify now.',
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: () => _startVerification(context),
        child: pill,
      ),
    );
  }
}

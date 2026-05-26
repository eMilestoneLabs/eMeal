import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/features/auth/widgets/otp_input_row.dart';

// ── OtpScreen ──────────────────────────────────────────────────────────────────

/// 6-box OTP verification screen.
///
/// Receives [OtpRouteExtra] via GoRouter extra:
///   - [identifier]: email or mobile the OTP was sent to
///   - [roleContext]: 'student' | 'admin' | 'event'
///   - [isSignup]: true if this OTP completes a signup flow
///
/// Features:
/// - Auto-submits when all 6 digits are entered
/// - 60-second countdown, resend enabled after timer
/// - Error: clears boxes, shows inline message
/// - Loading: boxes disabled, spinner shown
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.identifier,
    required this.roleContext,
    this.isSignup = false,
  });

  final String identifier;
  final String roleContext;
  final bool isSignup;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  bool _isLoading = false;
  bool _isResending = false;
  String? _error;

  // Countdown
  static const _countdownSeconds = 60;
  int _secondsLeft = _countdownSeconds;
  Timer? _timer;
  bool get _canResend => _secondsLeft == 0;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    _secondsLeft = _countdownSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_secondsLeft > 0) {
          _secondsLeft--;
        } else {
          t.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify(String otp) async {
    if (otp.length < 6) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = AuthProviderScope.of(context);
    final error = await auth.verifyOtp(
      identifier: widget.identifier,
      otp: otp,
      roleContext: widget.roleContext,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _routeAfterAuth(auth);
  }

  void _routeAfterAuth(AuthProvider auth) {
    final user = auth.currentUser;
    if (user == null) return;
    if (user.role.isAdminGroup) {
      context.go(RouteNames.adminDashboard);
    } else if (user.role.isEventGroup) {
      context.go(RouteNames.eventAdminDashboard);
    } else {
      context.go(RouteNames.studentDashboard);
    }
  }

  Future<void> _resend() async {
    if (!_canResend || _isResending) return;
    setState(() {
      _error = null;
      _isResending = true;
    });

    // Request a new OTP via the provider (mock: no-op; live: POST /v1/auth/otp/request).
    final errorMsg = await AuthProviderScope.of(context)
        .requestOtp(identifier: widget.identifier);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (errorMsg != null) {
      setState(() => _error = errorMsg);
      return;
    }

    _startCountdown();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('OTP resent to ${widget.identifier}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color get _roleColor => switch (widget.roleContext) {
        'admin' => AppColors.secondary,
        'event' => AppColors.vacation,
        _ => AppColors.primary,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // Icon
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.sms_rounded, size: 30, color: _roleColor),
                ),
              ),
              const SizedBox(height: 24),

              Text(
                'Enter OTP',
                style: AppTypography.displaySmall.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: AppTypography.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to\n'),
                    TextSpan(
                      text: widget.identifier,
                      style: AppTypography.bodySmall.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // OTP boxes
              OtpInputRow(
                enabled: !_isLoading,
                onCompleted: _verify,
              ),

              // Error
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    colorScheme.error.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 16, color: colorScheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: AppTypography.bodySmall
                                      .copyWith(color: colorScheme.error),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              if (_isLoading) ...[
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _roleColor,
                    ),
                  ),
                ),
              ],

              const Spacer(),

              // Countdown / resend
              Center(
                child: _secondsLeft > 0
                    ? Text(
                        'Resend OTP in ${_secondsLeft}s',
                        style: AppTypography.bodySmall.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : _isResending
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _roleColor,
                            ),
                          )
                        : TextButton(
                            onPressed: _resend,
                            child: Text(
                              'Resend OTP',
                              style: AppTypography.bodySmall.copyWith(
                                color: _roleColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}


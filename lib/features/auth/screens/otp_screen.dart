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
    this.purpose = 'login',
    this.autoRequest,
    this.popOnSuccess = false,
  });

  final String identifier;
  final String roleContext;
  final bool isSignup;

  /// When true, a successful verification pops back to the caller (Profile
  /// "Verify now") instead of routing to a dashboard.
  final bool popOnSuccess;

  /// Backend OTP flow: `'login'` (code requested on entry) or `'signup'`
  /// (code already sent during account creation — resend uses this purpose).
  final String purpose;

  /// Whether to request a code on entry. Defaults to true for `login`
  /// (nothing pre-sent) and false for `signup` (code sent during signup).
  final bool? autoRequest;

  bool get _shouldAutoRequest => autoRequest ?? (purpose == 'login');

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  bool _isLoading = false;
  bool _isResending = false;
  String? _error;

  // ── Live-Test-15 ISSUE-5 (RC-D): route arguments pinned to State ──────────
  //
  // Every parameter of this screen arrives through `state.extra`, which is NOT
  // part of the URI. GoRouter re-runs its builders whenever `refreshListenable`
  // (the AuthProvider) notifies, and this flow notifies mid-verification — the
  // login route one screen up already documents `extra` being dropped by such a
  // refresh, which is why its roleContext travels in the query string instead.
  //
  // If that happened here the screen would silently rebuild with identifier=''
  // and popOnSuccess=false: the OTP would be requested for an empty address and
  // success would `go()` to a dashboard instead of returning the user to the
  // page they started from (the "Critical Navigation Requirement").
  //
  // Pinning the values in State fixes it without putting the user's EMAIL into
  // a route URI (which would leak it into the address bar on web and into any
  // navigation logging). State survives the rebuild; the arguments survive with
  // it. The `??` keeps whichever value actually arrived first.
  late final String _identifier = widget.identifier;
  late final String _roleContext = widget.roleContext;
  late final String _purpose = widget.purpose;
  late final bool _popOnSuccess = widget.popOnSuccess;
  late final bool _shouldAutoRequest = widget._shouldAutoRequest;
  late final bool _isSignup = widget.isSignup;

  // Countdown
  static const _countdownSeconds = 60;
  int _secondsLeft = _countdownSeconds;
  Timer? _timer;
  bool get _canResend => _secondsLeft == 0;

  @override
  void initState() {
    super.initState();
    // Login OTP (and profile "Verify now") request the code when the screen
    // opens. Signup OTP was already sent during account creation, so we only
    // start the resend timer.
    if (_shouldAutoRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestInitialOtp());
    }
    _startCountdown();
  }

  /// Send the first OTP for the Email-OTP login flow (AUTH-015). Errors surface
  /// inline; the resend timer still runs so the user can retry.
  Future<void> _requestInitialOtp() async {
    final error = await AuthProviderScope.of(context).requestOtp(
      identifier: _identifier,
      purpose: _purpose,
    );
    if (!mounted || error == null) return;
    setState(() => _error = error);
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
    // Live-Test-15 ISSUE-5 (RC-B): pick the verifier by whether a SESSION
    // ALREADY EXISTS, not by how this screen was opened.
    //
    // `verifyOtp` is the OTP-LOGIN state machine: it flips to AuthLoading
    // before the call and AuthUnauthenticated on failure. That is right when
    // nobody is signed in — and destructive when someone is. BOTH authenticated
    // entries land here: profile "Verify now" (popOnSuccess) AND the
    // post-signup verification (signup establishes the session first). In both,
    // a mistyped digit used to leave the app unauthenticated with the session
    // still in memory, so backing out hit the router redirect and dumped the
    // user on /role-select — they appeared logged out for one wrong OTP.
    //
    // Keying off `isAuthenticated` covers every authenticated entry point and
    // leaves the genuine OTP-LOGIN path byte-identical.
    final error = auth.isAuthenticated
        ? await auth.verifyEmailOtp(
            identifier: _identifier,
            otp: otp,
            purpose: _purpose,
          )
        : await auth.verifyOtp(
            identifier: _identifier,
            otp: otp,
            roleContext: _roleContext,
            purpose: _purpose,
          );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      setState(() => _error = error);
      return;
    }

    // Profile "Verify now": stay in place — pop back so the verified badge
    // updates on the profile the user came from (Issue 6).
    if (_popOnSuccess) {
      // verifyEmailOtp already adopted the freshly-verified session, so the
      // badge is correct the moment we pop. This reconcile stays as a
      // belt-and-braces sync for any server-side field the OTP response does
      // not carry; it is awaited but costs one cached profile read.
      await auth.refreshCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email verified ✓'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      context.pop();
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
        .requestOtp(identifier: _identifier, purpose: _purpose);

    if (!mounted) return;
    setState(() => _isResending = false);

    if (errorMsg != null) {
      setState(() => _error = errorMsg);
      return;
    }

    _startCountdown();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('OTP resent to $_identifier'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color get _roleColor => switch (_roleContext) {
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
        // UI-007/008 + Part 4 §7: scrollable and keyboard-aware so the OTP boxes
        // and resend action are never hidden behind the keyboard on small screens.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
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
                      text: _identifier,
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

              // Signup already created the account and issued tokens — email
              // verification is optional for login. If the OTP email is slow
              // or lands in spam, the user must never be trapped here: let
              // them continue and verify later from Profile ("Verify now").
              if (_isSignup && !_popOnSuccess) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () =>
                            _routeAfterAuth(AuthProviderScope.of(context)),
                    child: Text(
                      'Skip for now — verify later from Profile',
                      style: AppTypography.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


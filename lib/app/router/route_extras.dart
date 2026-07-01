// GoRouter extra data classes.
//
// These are passed via GoRouter.push / GoRouter.go extra parameter
// and decoded in route builders inside app_router.dart.
//
// Defined here (not in app_router.dart) so they can be imported by both
// the router AND the screens that create/consume them.

/// Carries the role context string to [LoginScreen].
/// Values: 'student' | 'admin' | 'event'
class AuthRouteExtra {
  const AuthRouteExtra({required this.roleContext});
  final String roleContext;
}

/// Carries context from [LoginScreen] / signup screens to [OtpScreen].
///
/// [purpose] selects the backend OTP flow:
///   - `'login'`  → Email OTP login (code requested on screen entry)
///   - `'signup'` → post-signup email verification (code already sent on signup)
/// [isSignup] is true when this OTP completes account creation (AUTH-036/041).
class OtpRouteExtra {
  const OtpRouteExtra({
    required this.identifier,
    required this.roleContext,
    this.purpose = 'login',
    this.isSignup = false,
    this.autoRequest,
    this.popOnSuccess = false,
  });
  final String identifier;
  final String roleContext;
  final String purpose;
  final bool isSignup;

  /// When true, a successful verification pops back to the caller (e.g. Profile
  /// "Verify now") instead of routing to a dashboard — so the user sees the
  /// verified badge update in place.
  final bool popOnSuccess;

  /// Whether the screen should request a fresh code on entry. Defaults to true
  /// for `login` (no code pre-sent) and false for `signup` (code sent on signup).
  /// Profile "Verify now" passes true with `signup` to trigger a fresh code.
  final bool? autoRequest;
}

/// Carries the identifier + role context from [ForgotPasswordScreen] to
/// [ResetPasswordScreen] so, after a successful reset, the user is returned to
/// the SAME workspace login (Student vs Admin), never defaulted to Student.
class ResetRouteExtra {
  const ResetRouteExtra({
    required this.identifier,
    required this.roleContext,
  });
  final String identifier;
  final String roleContext;
}

/// Carries event guest party data from [EventGuestJoinScreen] to
/// [EventGuestShell] so the shell can initialise the party without
/// a second network call.
class EventGuestJoinExtra {
  const EventGuestJoinExtra({
    required this.primaryName,
    required this.adultsCount,
    required this.childrenCount,
    required this.joinCode,
  });
  final String primaryName;
  final int adultsCount;
  final int childrenCount;
  final String joinCode;
}

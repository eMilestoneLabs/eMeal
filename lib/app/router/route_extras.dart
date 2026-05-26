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

/// Carries context from [LoginScreen] to [OtpScreen].
class OtpRouteExtra {
  const OtpRouteExtra({
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

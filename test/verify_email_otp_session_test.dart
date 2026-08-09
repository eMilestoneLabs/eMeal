import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/repositories/auth_repository.dart';
import 'package:smart_meal_management/features/auth/models/auth_session.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Live-Test-15 ISSUE-5 (RC-B) — IN-SESSION EMAIL VERIFICATION.
///
/// `verifyOtp` is the OTP-**login** state machine: it flips the session to
/// AuthLoading before the call and to AuthUnauthenticated on failure. That is
/// correct when nobody is signed in — and destructive when someone is.
///
/// BOTH authenticated entry points ("Verify now" from the profile badge AND
/// post-signup verification) previously ran that machine, so ONE MISTYPED
/// DIGIT left the app unauthenticated with the session still in memory: the
/// router's redirect then dumped the user on /role-select the moment they
/// backed out. They appeared logged out.
///
/// `verifyEmailOtp` exists to make that impossible. These cases pin it:
///   • wrong / expired / rate-limited code → session SURVIVES untouched
///   • correct code                        → session upgraded, still signed in
///   • no state churn on the failure path  → nothing for the router to react to
class _FakeAuthRepo extends AuthRepository {
  // Both fields are assigned per-case after construction (see `_signedIn`), so
  // the constructor takes no parameters.
  AuthSession? session;
  Failure? failure;
  int calls = 0;
  String? lastPurpose;

  @override
  Future<Result<AuthSession>> verifyOtp({
    required String identifier,
    required String otp,
    required String roleContext,
    String purpose = 'login',
  }) async {
    calls++;
    lastPurpose = purpose;
    return failure != null ? Err(failure!) : Ok(session!);
  }
}

UserModel user(String id, {bool verified = false}) => UserModel(
      id: id,
      name: 'Test',
      email: 'test@example.com',
      role: UserRole.student,
      organizationId: 'org1',
      emailVerified: verified,
    );

AuthSession sessionFor(UserModel u) => AuthSession(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      user: u,
    );

/// Establishes a genuine signed-in session through the PUBLIC api (a
/// successful in-session verification), so the failure cases below start from
/// the exact state a real "Verify now" tap starts from.
Future<AuthProvider> _signedIn(_FakeAuthRepo repo, UserModel u) async {
  repo.session = sessionFor(u);
  repo.failure = null;
  final auth = AuthProvider(repo: repo);
  await auth.verifyEmailOtp(identifier: u.email, otp: '999999');
  return auth;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('WRONG OTP does NOT sign the user out (the regression)', () async {
    final repo = _FakeAuthRepo();
    final auth = await _signedIn(repo, user('u1'));
    repo.failure = const NetworkFailure(message: 'Invalid OTP', statusCode: 401);
    repo.session = null;

    expect(auth.isAuthenticated, isTrue);
    final before = auth.state;

    final err = await auth.verifyEmailOtp(identifier: 'test@example.com', otp: '000000');

    expect(err, 'Invalid OTP', reason: 'the error is surfaced inline');
    expect(auth.isAuthenticated, isTrue,
        reason: 'a mistyped digit must NEVER end the session');
    expect(auth.currentUser?.id, 'u1');
    expect(identical(auth.state, before), isTrue,
        reason: 'no state churn at all — nothing for the router to react to');
  });

  test('EXPIRED OTP behaves the same — session survives', () async {
    final repo = _FakeAuthRepo();
    final auth = await _signedIn(repo, user('u1'));
    repo.failure = const NetworkFailure(message: 'OTP expired', statusCode: 401);
    repo.session = null;

    final err = await auth.verifyEmailOtp(identifier: 'test@example.com', otp: '111111');
    expect(err, 'OTP expired');
    expect(auth.isAuthenticated, isTrue);
  });

  test('RATE-LIMITED (429) behaves the same — session survives', () async {
    final repo = _FakeAuthRepo();
    final auth = await _signedIn(repo, user('u1'));
    repo.failure =
        const NetworkFailure(message: 'Too many requests', statusCode: 429);
    repo.session = null;

    await auth.verifyEmailOtp(identifier: 'test@example.com', otp: '222222');
    expect(auth.isAuthenticated, isTrue);
  });

  test('CORRECT OTP upgrades the session in place (verified, still signed in)',
      () async {
    final repo = _FakeAuthRepo();
    final auth = await _signedIn(repo, user('u1')); // unverified
    repo.session = sessionFor(user('u1', verified: true));

    expect(auth.currentUser?.emailVerified, isFalse);

    final err = await auth.verifyEmailOtp(identifier: 'test@example.com', otp: '123456');

    expect(err, isNull);
    expect(auth.isAuthenticated, isTrue, reason: 'never dropped mid-flow');
    expect(auth.currentUser?.emailVerified, isTrue,
        reason: 'UI reflects verified with no refresh/restart/re-login');
    expect(auth.currentUser?.id, 'u1', reason: 'same account');
  });

  test('defaults to the signup purpose the badge/gate request the code with',
      () async {
    final repo = _FakeAuthRepo();
    final auth = await _signedIn(repo, user('u1'));
    repo.session = sessionFor(user('u1', verified: true));

    await auth.verifyEmailOtp(identifier: 'test@example.com', otp: '123456');
    expect(repo.lastPurpose, 'signup',
        reason: 'must match the purpose the OTP was issued under');
  });
}

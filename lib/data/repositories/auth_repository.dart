import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_auth_repository.dart';
import 'package:smart_meal_management/data/mock/mock_auth_service.dart';
// PHASE_B6: uncomment this import when wiring real API calls.
// import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/features/auth/models/auth_session.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Auth repository with dual-mode dispatch based on [EnvConfig.mockAuthEnabled].
///
/// ## Mock mode ([EnvConfig.mockAuthEnabled] == true — default in development)
///
/// - Validates credentials against [MockAuthService] in-memory.
/// - Persists sessions to [AuthStorageService] so the user stays logged in.
/// - Simulates realistic async latency for all operations.
///
/// ## Live mode ([EnvConfig.mockAuthEnabled] == false — staging + production)
///
/// - Calls the NestJS backend via [DioApiService]:
///     POST /v1/auth/login  → JWT access + refresh tokens
///     POST /v1/auth/signup
///     POST /v1/auth/otp/request
///     POST /v1/auth/otp/verify
/// - Stubs are marked with `// PHASE_B6: implement` comments so integration
///   work is easy to locate.
///
/// ## Switching modes
///
/// Set `mockAuthEnabled: false` in [EnvConfig._staging] or [EnvConfig._production]
/// (already done) and remove `mockAuthEnabled: true` from [EnvConfig._development]
/// when you're ready to point development at a local NestJS instance.
class AuthRepository implements IAuthRepository {
  // Whether to use mock in-memory auth or the real NestJS backend.
  static bool get _isMock => EnvConfig.current.mockAuthEnabled;
  AuthSession? _session;

  final _storage = AuthStorageService.instance;

  /// In-memory profile cache for mock mode.
  ///
  /// Populated on login/signup so [getProfile] and [updateProfile] can
  /// operate without a network round-trip.  Keyed by userId.
  final Map<String, UserModel> _profileCache = {};

  static Future<void> _delay([int ms = 200]) =>
      Future.delayed(Duration(milliseconds: ms));

  // ── Login ──────────────────────────────────────────────────────────────────

  @override
  Future<Result<AuthSession>> login({
    required String identifier,
    required String password,
    required String roleContext,
  }) async {
    if (!_isMock) {
      // PHASE_B6: implement — call POST /v1/auth/login via DioApiService.
      // Example:
      //   final result = await DioApiService.instance.post<Map<String, dynamic>>(
      //     ApiEndpoints.auth.login,
      //     body: {'identifier': identifier, 'password': password},
      //     requiresAuth: false,
      //   );
      //   return result.fold(
      //     (failure) => Err(failure),
      //     (body) async {
      //       final session = AuthSession.fromJson(body);
      //       await _storage.saveSession(session);
      //       return Ok(session);
      //     },
      //   );
      return const Err(NetworkFailure(
        message: 'Live API integration not yet wired. Enable mock mode for development.',
      ));
    }

    await _delay(400);

    final user = MockAuthService.authenticate(identifier, password);
    if (user == null) {
      return const Err(AuthFailure(message: 'Invalid email/mobile or password. Please try again.'));
    }

    // Role context guard: prevent cross-role login (e.g. student logging in as admin).
    final roleOk = switch (roleContext) {
      'admin'   => user.role.isAdminGroup,
      'event'   => user.role.isEventGroup,
      _         => user.role.isStudentGroup,
    };
    if (!roleOk) {
      return Err(AuthFailure(
        message: 'This account does not have ${_roleLabel(roleContext)} access.',
      ));
    }

    final session = _buildSession(user);
    _session = session;
    _profileCache[user.id] = user;
    await _storage.saveSession(session);
    return Ok(session);
  }

  // ── OTP ────────────────────────────────────────────────────────────────────

  @override
  Future<Result<Unit>> requestOtp({required String identifier}) async {
    if (!_isMock) {
      // PHASE_B6: implement — call POST /v1/auth/otp/request via DioApiService.
      return const Err(NetworkFailure(
        message: 'Live API integration not yet wired. Enable mock mode for development.',
      ));
    }
    await _delay(300);
    // Mock: just succeed — real impl sends SMS/email via NestJS.
    final user = MockAuthService.findByIdentifier(identifier);
    if (user == null) {
      return const Err(AuthFailure(message: 'No account found for this identifier.'));
    }
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<AuthSession>> verifyOtp({
    required String identifier,
    required String otp,
    required String roleContext,
  }) async {
    if (!_isMock) {
      // PHASE_B6: implement — call POST /v1/auth/otp/verify via DioApiService.
      return const Err(NetworkFailure(
        message: 'Live API integration not yet wired. Enable mock mode for development.',
      ));
    }
    await _delay(500);

    // Mock: accept '123456' as valid OTP for any registered identifier.
    if (otp != '123456') {
      return const Err(AuthFailure(message: 'Incorrect OTP. Please try again.'));
    }

    final user = MockAuthService.findByIdentifier(identifier);
    if (user == null) {
      return const Err(AuthFailure(message: 'No account found for this identifier.'));
    }

    // Role context guard.
    final roleOk = switch (roleContext) {
      'admin' => user.role.isAdminGroup,
      'event' => user.role.isEventGroup,
      _       => user.role.isStudentGroup,
    };
    if (!roleOk) {
      return Err(AuthFailure(
        message: 'This account does not have ${_roleLabel(roleContext)} access.',
      ));
    }

    final session = _buildSession(user);
    _session = session;
    _profileCache[user.id] = user;
    await _storage.saveSession(session);
    return Ok(session);
  }

  // ── Reset password ────────────────────────────────────────────────────────

  /// Validate [otp] for [identifier] and update the stored password.
  ///
  /// Mock: accepts '123456' as valid OTP (matches [MockAuthService] OTP logic).
  /// Returns [Ok(Unit)] on success so the screen can show the success state
  /// without establishing a new session — the user must re-login.
  ///
  /// PHASE_B6: POST /v1/auth/reset-password
  ///   body: { identifier, otp, newPassword }
  ///   success: 200 — redirect user to login
  Future<Result<Unit>> resetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    if (!_isMock) {
      // PHASE_B6: implement — call POST /v1/auth/reset-password via DioApiService.
      return const Err(NetworkFailure(
        message: 'Live API integration not yet wired. Enable mock mode for development.',
      ));
    }
    await _delay(500);

    // Mock: validate identifier exists.
    final user = MockAuthService.findByIdentifier(identifier);
    if (user == null) {
      return const Err(AuthFailure(message: 'No account found for this email or mobile number.'));
    }

    // Mock: accept only '123456' as a valid OTP.
    if (otp != '123456') {
      return const Err(AuthFailure(message: 'Invalid code. Please check the OTP you received.'));
    }

    // Mock: update in-memory credentials so re-login with new password works.
    MockAuthService.registerSignupCredentials(user: user, password: newPassword);
    return const Ok(Unit.instance);
  }

  // ── Signup ─────────────────────────────────────────────────────────────────

  @override
  Future<Result<AuthSession>> signup({
    required String name,
    required UserRole role,
    required String mobile,
    required String email,
    required String password,
    required LoginPreference loginPreference,
    int? age,
    String? gender,
    // Event admin extras
    String? eventName,
    EventType? eventType,
    DateTime? eventDate,
    int? expectedGuestCount,
    bool autoDeleteEvent = false,
  }) async {
    if (!_isMock) {
      // PHASE_B6: implement — call POST /v1/auth/signup via DioApiService.
      return const Err(NetworkFailure(
        message: 'Live API integration not yet wired. Enable mock mode for development.',
      ));
    }
    await _delay(500);

    // Mock: generate a unique-enough ID from email + timestamp.
    final id = 'usr_${role.name}_${DateTime.now().millisecondsSinceEpoch}';
    final user = MockAuthService.createSignupUser(
      id: id,
      name: name,
      email: email,
      phone: mobile,
      role: role,
      organizationId: role.isEventGroup ? 'org_event_$id' : 'org_new',
    );

    // Register credentials so the user can re-login after session expiry.
    MockAuthService.registerSignupCredentials(user: user, password: password);

    final session = _buildSession(user);
    _session = session;
    _profileCache[user.id] = user;
    await _storage.saveSession(session);
    return Ok(session);
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  @override
  Future<Result<Unit>> logout() async {
    await _delay();
    _session = null;
    await _storage.clearSession();
    return const Ok(Unit.instance);
  }

  // ── Token refresh ──────────────────────────────────────────────────────────

  @override
  Future<Result<AuthSession>> refreshToken({required String token}) async {
    await _delay();
    if (_session == null) {
      return const Err(AuthFailure(message: 'No active session to refresh.'));
    }
    final user = _session!.user;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final refreshed = _session!.copyWith(
      accessToken: 'mock_access_${user.id}_$ts',
      refreshToken: 'mock_refresh_${user.id}_$ts',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      user: user,
    );
    _session = refreshed;
    await _storage.saveSession(refreshed);
    return Ok(refreshed);
  }

  // ── Profile ────────────────────────────────────────────────────────────────

  @override
  Future<Result<UserModel>> getProfile({required String userId}) async {
    await _delay();
    // Return from in-memory cache first.
    final cached = _profileCache[userId];
    if (cached != null) return Ok(cached);
    // Fall back to the active session's user if IDs match.
    if (_session?.user.id == userId) {
      _profileCache[userId] = _session!.user;
      return Ok(_session!.user);
    }
    return const Err(AuthFailure(message: 'User profile not found.'));
  }

  @override
  Future<Result<UserModel>> updateProfile({required UserModel user}) async {
    await _delay(300);
    _profileCache[user.id] = user;
    // Keep the active session in sync if this is the current user.
    if (_session?.user.id == user.id) {
      final updated = _session!.copyWith(user: user);
      _session = updated;
      await _storage.saveSession(updated);
    }
    return Ok(user);
  }

  @override
  Future<Result<AuthSession?>> restoreSession() async {
    try {
      final stored = await _storage.loadSession();
      if (stored == null) return const Ok(null);
      _session = stored;
      _profileCache[stored.user.id] = stored.user;
      return Ok(stored);
    } catch (_) {
      // If storage is unavailable or data is corrupted, treat as no session.
      return const Ok(null);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Builds a mock [AuthSession] for [user] with short-lived token strings.
  AuthSession _buildSession(UserModel user) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return AuthSession(
      accessToken: 'mock_access_${user.id}_$ts',
      refreshToken: 'mock_refresh_${user.id}_$ts',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      user: user,
    );
  }

  String _roleLabel(String context) => switch (context) {
        'admin' => 'Admin/Manager',
        'event' => 'Event',
        _ => 'Student/Guest',
      };
}

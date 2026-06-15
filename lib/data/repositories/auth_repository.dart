import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_auth_repository.dart';
import 'package:smart_meal_management/data/mock/mock_auth_service.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
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
      // B10 LIVE: POST /auth/login — backend contract:
      // { accessToken, refreshToken, expiresIn: 900, user: {...} }
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/login',
        body: {'identifier': identifier.trim(), 'password': password},
        requiresAuth: false,
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final AuthSession session;
          try {
            session = AuthSession.fromJson(value);
          } catch (e) {
            return Err(UnexpectedFailure(message: 'Unexpected login response: $e'));
          }
          // Role-context guard mirrors mock behavior — prevents cross-role login.
          final liveRoleOk = switch (roleContext) {
            'admin' => session.user.role.isAdminGroup,
            'event' => session.user.role.isEventGroup,
            _ => session.user.role.isStudentGroup,
          };
          if (!liveRoleOk) {
            return Err(AuthFailure(
              message: 'This account does not have ${_roleLabel(roleContext)} access.',
            ));
          }
          _session = session;
          _profileCache[session.user.id] = session.user;
          await _storage.saveSession(session);
          return Ok(session);
      }
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
      // B10 LIVE: POST /auth/otp/request — { identifier, purpose: 'login' }
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/otp/request',
        body: {'identifier': identifier.trim(), 'purpose': 'login'},
        requiresAuth: false,
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
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
      // B10 LIVE: POST /auth/otp/verify — returns a full auth session.
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/otp/verify',
        body: {'identifier': identifier.trim(), 'otp': otp},
        requiresAuth: false,
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final AuthSession session;
          try {
            session = AuthSession.fromJson(value);
          } catch (e) {
            return Err(UnexpectedFailure(message: 'Unexpected OTP response: $e'));
          }
          final liveRoleOk = switch (roleContext) {
            'admin' => session.user.role.isAdminGroup,
            'event' => session.user.role.isEventGroup,
            _ => session.user.role.isStudentGroup,
          };
          if (!liveRoleOk) {
            return Err(AuthFailure(
              message: 'This account does not have ${_roleLabel(roleContext)} access.',
            ));
          }
          _session = session;
          _profileCache[session.user.id] = session.user;
          await _storage.saveSession(session);
          return Ok(session);
      }
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
      // B10 LIVE: POST /auth/reset-password — { identifier, otp, newPassword }
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/reset-password',
        body: {
          'identifier': identifier.trim(),
          'otp': otp,
          'newPassword': newPassword,
        },
        requiresAuth: false,
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
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
      // B10 LIVE: POST /auth/register — single endpoint, backend dispatches
      // by `role` to student/admin/eventAdmin signup. Backend uses `phone`
      // (never `mobile`) and `autoDeleteAfter7Days` (never `autoDeleteEvent`).
      final body = <String, dynamic>{
        'name': name.trim(),
        'role': role.name,
        'email': email.trim(),
        'phone': mobile.trim(),
        'password': password,
        'loginPreference': loginPreference.name,
        if (age != null) 'age': age,
        if (gender != null) 'gender': gender,
        // Event admin extras — backend EventAdminSignupDto:
        if (eventName != null) 'eventName': eventName,
        if (eventType != null) 'eventType': eventType.name,
        if (eventDate != null) 'eventDate': eventDate.toIso8601String(),
        if (expectedGuestCount != null) 'expectedGuestCount': expectedGuestCount,
        if (autoDeleteEvent) 'autoDeleteAfter7Days': true,
      };
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/register',
        body: body,
        requiresAuth: false,
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final AuthSession session;
          try {
            session = AuthSession.fromJson(value);
          } catch (e) {
            return Err(UnexpectedFailure(message: 'Unexpected signup response: $e'));
          }
          _session = session;
          _profileCache[session.user.id] = session.user;
          await _storage.saveSession(session);
          return Ok(session);
      }
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
    if (!_isMock) {
      // B10 LIVE: best-effort server-side revocation (refresh-token family),
      // then ALWAYS clear locally — logout must never strand the user.
      final refreshToken = _session?.refreshToken;
      try {
        await DioApiService.instance.post<Map<String, dynamic>>(
          '/auth/logout',
          body: {if (refreshToken != null) 'refreshToken': refreshToken},
        );
      } catch (_) {
        // Network failure must not block local logout.
      }
      _session = null;
      await _storage.clearSession();
      return const Ok(Unit.instance);
    }
    await _delay();
    _session = null;
    await _storage.clearSession();
    return const Ok(Unit.instance);
  }

  // ── Token refresh ──────────────────────────────────────────────────────────

  @override
  Future<Result<AuthSession>> refreshToken({required String token}) async {
    if (!_isMock) {
      // B10 LIVE: POST /auth/refresh — rotating refresh-token family.
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/refresh',
        body: {'refreshToken': token},
        requiresAuth: false,
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final AuthSession session;
          try {
            session = AuthSession.fromJson(value);
          } catch (e) {
            return Err(UnexpectedFailure(message: 'Unexpected refresh response: $e'));
          }
          _session = session;
          _profileCache[session.user.id] = session.user;
          await _storage.saveSession(session);
          return Ok(session);
      }
    }
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
    if (!_isMock) {
      // B10 LIVE: GET /auth/me — returns the full UserModel for the JWT user.
      final result = await DioApiService.instance.get<Map<String, dynamic>>('/auth/me');
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final user = UserModel.fromJson(value);
          _profileCache[user.id] = user;
          if (_session != null && _session!.user.id == user.id) {
            _session = _session!.copyWith(user: user);
            await _storage.saveSession(_session!);
          }
          return Ok(user);
      }
    }
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
    if (!_isMock) {
      // B10 LIVE: PATCH /users/me — UpdateUserDto whitelist:
      // name, email, phone, avatarUrl, gender, age, isVacationMode,
      // isDefaultAttendance, remindersEnabled, loginPreference.
      final result = await DioApiService.instance.patch<Map<String, dynamic>>(
        '/users/me',
        body: {
          'name': user.name,
          // Issue #2: persist email edits (backend UpdateUserDto accepts it).
          if (user.email.trim().isNotEmpty) 'email': user.email.trim(),
          // Only send phone when non-empty — the backend regex rejects '' and
          // would turn a valid name/email edit into a false 422 failure.
          if (user.phone != null && user.phone!.trim().isNotEmpty)
            'phone': user.phone!.trim(),
          if (user.gender != null) 'gender': user.gender,
          if (user.age != null) 'age': user.age,
          if (user.avatarUrl != null) 'avatarUrl': user.avatarUrl,
          'isVacationMode': user.isVacationMode,
          'isDefaultAttendance': user.isDefaultAttendance,
        },
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final updated = UserModel.fromJson(value);
          _profileCache[updated.id] = updated;
          if (_session != null && _session!.user.id == updated.id) {
            _session = _session!.copyWith(user: updated);
            await _storage.saveSession(_session!);
          }
          return Ok(updated);
      }
    }
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
      // allowExpired: a cold start after the 15-min access token lapsed must NOT
      // force re-login while the refresh token is still valid — GET /auth/me
      // below triggers the interceptor's transparent refresh.
      final stored = await _storage.loadSession(allowExpired: true);
      if (stored == null) return const Ok(null);
      if (!_isMock) {
        // B10 LIVE: validate the stored token against GET /auth/me.
        // DioApiService transparently refreshes on 401 (rotating family);
        // if validation still fails the user must log in again.
        final result = await DioApiService.instance.get<Map<String, dynamic>>('/auth/me');
        switch (result) {
          case Err():
            return const Ok(null); // invalid/expired → force re-login
          case Ok(:final value):
            final user = UserModel.fromJson(value);
            // Storage may hold rotated tokens (refreshed by the interceptor).
            final latest = await _storage.loadSession() ?? stored;
            final refreshed = latest.copyWith(user: user);
            _session = refreshed;
            _profileCache[user.id] = user;
            await _storage.saveSession(refreshed);
            return Ok(refreshed);
        }
      }
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

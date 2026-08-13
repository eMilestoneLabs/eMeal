import 'dart:async';

import 'package:smart_meal_management/core/constants/api_endpoints.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_auth_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/features/auth/models/auth_session.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Auth repository — talks to the live NestJS backend via [DioApiService].
///
/// Endpoints:
///   POST `/auth/login` · `/auth/register` · `/auth/otp/request` ·
///   `/auth/otp/verify` · `/auth/forgot-password` · `/auth/reset-password` ·
///   `/auth/refresh` · `/auth/logout`
///   GET  `/auth/me`   ·   PATCH `/users/me`
///
/// All methods return [Result<T>] (never throw); sessions are persisted via
/// [AuthStorageService] so the user stays logged in across restarts.
class AuthRepository implements IAuthRepository {
  AuthSession? _session;

  final _storage = AuthStorageService.instance;

  /// In-memory profile cache, populated on login/refresh so repeated reads
  /// don't always round-trip. Keyed by userId.
  final Map<String, UserModel> _profileCache = {};

  // ── Login ──────────────────────────────────────────────────────────────────

  @override
  Future<Result<AuthSession>> login({
    required String identifier,
    required String password,
    required String roleContext,
  }) async {
    // POST /auth/login — backend contract: { accessToken, refreshToken, expiresIn, user }
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
        // Role-context guard — prevents cross-role login.
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

  // ── OTP ────────────────────────────────────────────────────────────────────

  @override
  Future<Result<Unit>> requestOtp({
    required String identifier,
    String purpose = 'login',
    String? roleContext,
  }) async {
    // Password recovery uses the dedicated endpoint (AUTH-017, Email-OTP only).
    // roleContext scopes the lookup so the backend can report a missing or
    // wrong-workspace account (Issue 5). Login/signup OTP use the generic endpoint.
    final Result<Map<String, dynamic>> result;
    if (purpose == 'reset') {
      result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/forgot-password',
        body: {
          'identifier': identifier.trim(),
          if (roleContext != null) 'roleContext': roleContext,
        },
        requiresAuth: false,
      );
    } else {
      result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/auth/otp/request',
        body: {'identifier': identifier.trim(), 'purpose': purpose},
        requiresAuth: false,
      );
    }
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  @override
  Future<Result<AuthSession>> verifyOtp({
    required String identifier,
    required String otp,
    required String roleContext,
    String purpose = 'login',
  }) async {
    // POST /auth/otp/verify — returns a full auth session.
    // purpose must match the request so the backend finds the OTP record.
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/auth/otp/verify',
      body: {'identifier': identifier.trim(), 'otp': otp, 'purpose': purpose},
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

  // ── Reset password ──────────────────────────────────────────────────────────

  /// POST /auth/reset-password — { identifier, otp, newPassword }.
  /// On success the user must re-login (no session is established here).
  Future<Result<Unit>> resetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
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
    String? organizationName,
    // Event admin extras
    String? eventName,
    EventType? eventType,
    DateTime? eventDate,
    int? expectedGuestCount,
    bool autoDeleteEvent = false,
  }) async {
    // POST /auth/register — single endpoint, backend dispatches by `role` to
    // student/admin/eventAdmin signup. Backend uses `phone` (never `mobile`)
    // and `autoDeleteAfter7Days` (never `autoDeleteEvent`).
    final body = <String, dynamic>{
      'name': name.trim(),
      'role': role.name,
      'email': email.trim(),
      'phone': mobile.trim(),
      'password': password,
      'loginPreference': loginPreference.name,
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      if (organizationName != null && organizationName.trim().isNotEmpty)
        'organizationName': organizationName.trim(),
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

  // ── Logout ─────────────────────────────────────────────────────────────────

  @override
  Future<Result<Unit>> logout() async {
    // Issue 1 (sign-out delay): clear the local session FIRST and FULLY, then
    // revoke on the server FIRE-AND-FORGET — so sign-out is instant and never
    // blocks on the network (a slow/offline link must not stall the UI).
    //
    // Ordering matters: storage is cleared BEFORE the revocation call, and the
    // revocation goes through `revokeSession` (which does no storage I/O and no
    // token refresh). This removes the ghost-session race — the interceptor's
    // proactive-refresh path could otherwise re-persist a session AFTER we
    // cleared it (likely on an idle logout with an expired access token) — and
    // the cross-account clobber if the user re-logs in immediately.
    final session = _session;
    _session = null;
    await _storage.clearSession();
    if (session != null) {
      unawaited(
        DioApiService.instance.revokeSession(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
        ),
      );
    }
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<Unit>> deleteAccount({String? password}) async {
    // Pass 14 (FR-DEL-011): DELETE /users/me — the server revokes every
    // session on every device, soft-removes memberships and anonymizes PII
    // in place (attendance/billing history is retained per policy). Unlike
    // logout this is NOT best-effort: the account must actually be deleted
    // server-side before we clear locally, so failures surface to the user.
    final result = await DioApiService.instance.delete<Map<String, dynamic>>(
      '/users/me',
      body: {
        'confirm': 'DELETE',
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok():
        _session = null;
        _profileCache.clear();
        await _storage.clearSession();
        return const Ok(Unit.instance);
    }
  }

  // ── Token refresh ──────────────────────────────────────────────────────────

  @override
  Future<Result<AuthSession>> refreshToken({required String token}) async {
    // POST /auth/refresh — rotating refresh-token family.
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

  // ── Profile ────────────────────────────────────────────────────────────────

  @override
  Future<Result<UserModel>> getProfile({required String userId}) async {
    // GET /auth/me — returns the full UserModel for the JWT user.
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

  @override
  Future<Result<UserModel>> updateProfile({required UserModel user}) async {
    // PATCH /users/me — UpdateUserDto whitelist:
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
        // SRS Module 01: Login Preference changeable from Profile settings.
        'loginPreference': user.loginPreference,
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

  // ── Per-group member settings ───────────────────────────────────────────
  //
  // These use the DEDICATED toggle endpoints rather than PATCH /users/me,
  // because only they accept a `groupId`. That is the whole point: the
  // user-level flags on /users/me govern EVERY group at once, which is what
  // let a vacation in one group suppress attendance and billing in another.
  // The session user is deliberately NOT rewritten here — the user-level flag
  // is still the inherited default for the member's other groups, so the
  // per-group value is returned to the caller instead of cached globally.

  @override
  Future<Result<bool>> setGroupVacationMode({
    required String userId,
    required String groupId,
    required bool enabled,
  }) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      ApiEndpoints.buildPath(ApiEndpoints.users.vacationMode, {'userId': userId}),
      body: {'enabled': enabled, 'groupId': groupId},
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        // Trust the server's echo — it applied the approval gate and the
        // membership check, so it is the authority on the resulting state.
        return Ok(value['isVacationMode'] as bool? ?? enabled);
    }
  }

  @override
  Future<Result<bool>> setGroupDefaultAttendance({
    required String userId,
    required String groupId,
    required bool enabled,
  }) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      ApiEndpoints.buildPath(ApiEndpoints.users.defaultAttendance, {'userId': userId}),
      body: {'enabled': enabled, 'groupId': groupId},
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        return Ok(value['isDefaultAttendance'] as bool? ?? enabled);
    }
  }

  @override
  Future<Result<AuthSession?>> restoreSession() async {
    try {
      // allowExpired: a cold start after the 15-min access token lapsed must NOT
      // force re-login while the refresh token is still valid — the Dio
      // interceptor transparently refreshes on the first authenticated call.
      final stored = await _storage.loadSession(allowExpired: true);
      if (stored == null) return const Ok(null);
      // INSTANT BOOT: return the stored session immediately — a pure local
      // read, ZERO network on the cold-start critical path. The old behavior
      // awaited GET /auth/me here, which held a returning user on the splash
      // screen for a full cold round-trip (and up to connectTimeout when the
      // first connection stalled). Server-side validation still happens:
      // [validateRestoredSession] runs the exact same /auth/me check in the
      // background (AuthProvider fires it unawaited), and every subsequent API
      // call is server-validated anyway — a revoked session dies on its first
      // real request. Security posture unchanged; only the waiting is gone.
      _session = stored;
      _profileCache[stored.user.id] = stored.user;
      return Ok(stored);
    } catch (_) {
      // If storage is unavailable or data is corrupted, treat as no session.
      return const Ok(null);
    }
  }

  /// Background validation of a restored session — the network half of the
  /// old [restoreSession], with byte-identical rules:
  ///   • `Ok(session)` — server confirmed (profile refreshed + rotated tokens
  ///     persisted), or a transient network error (keep stored optimistically).
  ///   • `Ok(null)`    — genuine AUTH rejection (401/403 after the transparent
  ///     refresh attempt): the session is dead; the caller must log out.
  /// Never throws.
  Future<Result<AuthSession?>> validateRestoredSession(
    AuthSession stored,
  ) async {
    try {
      // Validate the stored token against GET /auth/me. DioApiService
      // transparently refreshes on 401 (rotating family); if validation still
      // fails the user must log in again.
      final result =
          await DioApiService.instance.get<Map<String, dynamic>>('/auth/me');
      switch (result) {
        case Err(:final failure):
          // Only a genuine AUTH rejection (401/403 — token revoked or expired
          // beyond refresh) forces re-login. A transient NetworkFailure
          // (timeout / no connection / 5xx) on a cold start must NOT log the
          // user out — keep the stored session optimistically; the Dio
          // interceptor's transparent 401-refresh self-corrects on the first
          // authenticated call if the token is genuinely dead.
          if (failure is AuthFailure) {
            return const Ok(null);
          }
          _session = stored;
          _profileCache[stored.user.id] = stored.user;
          return Ok(stored);
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
    } catch (_) {
      // Unexpected local failure — keep the stored session; never log out here.
      return Ok(stored);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _roleLabel(String context) => switch (context) {
        'admin' => 'Admin/Manager',
        'event' => 'Event',
        _ => 'Student/Member',
      };
}

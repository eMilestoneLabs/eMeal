import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:smart_meal_management/data/repositories/auth_repository.dart';
import 'package:smart_meal_management/data/services/realtime_service.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/features/auth/models/auth_session.dart';
import 'package:smart_meal_management/features/auth/models/auth_state.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Central authentication state manager.
///
/// Holds the current [AuthState] and exposes:
///   - [initialize]  — restores persisted session on cold start
///   - [login]       — email-or-mobile + password (any role context)
///   - [loginWithOtp] / [verifyOtp] — passwordless OTP flow
///   - [signup]      — creates a new account (student / admin / event admin)
///   - [logout]      — clears session from memory + SharedPreferences
///   - [refreshUser] — in-memory user model patch (settings toggles etc.)
///
/// Consumed by [AuthProviderScope] via [InheritedNotifier].
class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthRepository? repo}) : _repo = repo ?? AuthRepository();

  final AuthRepository _repo;

  AuthState _state = const AuthUnknown();
  AuthSession? _session;

  /// In-memory avatar image bytes — used by profile screens for local
  /// image upload before a backend round-trip is available.
  Uint8List? _avatarBytes;

  // ── Getters ────────────────────────────────────────────────────────────────

  AuthState get state => _state;
  AuthSession? get session => _session;
  UserModel? get currentUser => _session?.user;
  bool get isAuthenticated => _state is AuthAuthenticated;
  bool get isLoading => _state is AuthLoading;

  /// Locally-picked avatar image bytes (not yet persisted to backend).
  Uint8List? get avatarBytes => _avatarBytes;

  // ── Initialise ─────────────────────────────────────────────────────────────

  /// Called once from [bootstrap.dart] / app startup.
  ///
  /// Restores a persisted session from SharedPreferences.
  /// Falls back to [AuthUnauthenticated] if none found or session expired.
  Future<void> initialize() async {
    _state = const AuthUnknown();
    notifyListeners();

    final result = await _repo.restoreSession();
    switch (result) {
      case Ok(:final value):
        // A restored session is usable if its access token is still valid OR it
        // carries a refresh token — in the latter case the Dio interceptor
        // transparently refreshes the access token on the first authenticated
        // call. This keeps a returning user logged in across access-token expiry
        // and flaky-network cold starts (no forced re-login); a genuinely dead
        // refresh token self-corrects to logout on that first call.
        if (value != null && (value.isValid || value.refreshToken.isNotEmpty)) {
          _session = value;
          _state = AuthAuthenticated(session: value);
          // B10: open realtime socket once a session is restored (no-op in mock).
          RealtimeService.instance.connect();
          // Restore persisted avatar bytes (fire-and-forget assignment; null is fine).
          _avatarBytes = await AuthStorageService.instance.loadAvatarBytes();
          // INSTANT BOOT: restoreSession is now a pure local read, so the server
          // check (GET /auth/me — profile refresh + rotated-token persist) runs
          // in the BACKGROUND. A genuine auth rejection self-corrects to logout
          // within seconds; the user never waits on the network at boot.
          unawaited(_validateRestoredSession(value));
        } else {
          _state = const AuthUnauthenticated();
        }
      case Err():
        _state = const AuthUnauthenticated();
    }
    notifyListeners();
  }

  /// Background half of the instant boot: runs the server-side session check
  /// that [initialize] no longer waits for. Same rules as the old blocking
  /// restore — a confirmed session silently refreshes the profile/tokens; a
  /// genuine AUTH rejection (revoked / dead refresh token) logs the user out;
  /// a transient network failure changes nothing. Never throws.
  Future<void> _validateRestoredSession(AuthSession stored) async {
    try {
      final result = await _repo.validateRestoredSession(stored);
      switch (result) {
        case Ok(:final value):
          if (value == null) {
            // Server rejected the session — self-correct to login. Guard: only
            // if the session we validated is still the active one, so a user
            // who logged out (or switched accounts) mid-validation is never
            // logged out of their NEW session by this stale result.
            if (_state is AuthAuthenticated &&
                _session?.user.id == stored.user.id) {
              await logout();
            }
          } else if (_state is AuthAuthenticated &&
              _session?.user.id == value.user.id) {
            // Confirmed: apply the refreshed profile / rotated tokens silently.
            _session = value;
            _state = AuthAuthenticated(session: value);
            notifyListeners();
          }
        case Err():
          break; // network trouble never logs the user out
      }
    } catch (_) {/* background validation must never disturb the app */}
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  /// Authenticate with [identifier] (email OR mobile) + [password].
  ///
  /// [roleContext] is one of `'student'`, `'admin'`, `'event'` — used to
  /// validate that the credential belongs to the expected role group.
  ///
  /// Returns `null` on success, or an error message string on failure.
  Future<String?> login({
    required String identifier,
    required String password,
    required String roleContext,
  }) async {
    _state = const AuthLoading();
    notifyListeners();

    final result = await _repo.login(
      identifier: identifier,
      password: password,
      roleContext: roleContext,
    );

    switch (result) {
      case Ok(:final value):
        _session = value;
        _state = AuthAuthenticated(session: value);
        RealtimeService.instance.connect(); // open the live realtime socket
        notifyListeners();
        return null; // success

      case Err(:final failure):
        _state = const AuthUnauthenticated();
        notifyListeners();
        return failure.message;
    }
  }

  // ── OTP flow ───────────────────────────────────────────────────────────────

  /// Request a one-time password for [identifier].
  ///
  /// Returns `null` on success, or an error message string on failure.
  Future<String?> requestOtp({
    required String identifier,
    String purpose = 'login',
    String? roleContext,
  }) async {
    final result = await _repo.requestOtp(
      identifier: identifier,
      purpose: purpose,
      roleContext: roleContext,
    );
    return switch (result) {
      Ok() => null,
      Err(:final failure) => failure.message,
    };
  }

  /// Verify [otp] for [identifier] and establish an authenticated session.
  ///
  /// Returns `null` on success, or an error message string on failure.
  Future<String?> verifyOtp({
    required String identifier,
    required String otp,
    required String roleContext,
    String purpose = 'login',
  }) async {
    _state = const AuthLoading();
    notifyListeners();

    final result = await _repo.verifyOtp(
      identifier: identifier,
      otp: otp,
      roleContext: roleContext,
      purpose: purpose,
    );

    switch (result) {
      case Ok(:final value):
        _session = value;
        _state = AuthAuthenticated(session: value);
        RealtimeService.instance.connect(); // open the live realtime socket
        notifyListeners();
        return null;

      case Err(:final failure):
        _state = const AuthUnauthenticated();
        notifyListeners();
        return failure.message;
    }
  }

  // ── Reset password ────────────────────────────────────────────────────────

  /// Validate [otp] and reset password for [identifier].
  ///
  /// Returns `null` on success, or an error message on failure.
  /// On success the user's session is NOT established — they must re-login.
  Future<String?> resetPassword({
    required String identifier,
    required String otp,
    required String newPassword,
  }) async {
    final result = await _repo.resetPassword(
      identifier: identifier,
      otp: otp,
      newPassword: newPassword,
    );
    return switch (result) {
      Ok() => null,
      Err(:final failure) => failure.message,
    };
  }

  // ── Signup ─────────────────────────────────────────────────────────────────

  /// Create a new account.
  ///
  /// All base fields are required. Pass event-specific fields for
  /// [UserRole.eventAdmin] signups.
  ///
  /// Returns `null` on success, or an error message string on failure.
  Future<String?> signup({
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
    _state = const AuthLoading();
    notifyListeners();

    final result = await _repo.signup(
      name: name,
      role: role,
      mobile: mobile,
      email: email,
      password: password,
      loginPreference: loginPreference,
      age: age,
      gender: gender,
      organizationName: organizationName,
      eventName: eventName,
      eventType: eventType,
      eventDate: eventDate,
      expectedGuestCount: expectedGuestCount,
      autoDeleteEvent: autoDeleteEvent,
    );

    switch (result) {
      case Ok(:final value):
        _session = value;
        _state = AuthAuthenticated(session: value);
        RealtimeService.instance.connect(); // open the live realtime socket
        notifyListeners();
        return null;

      case Err(:final failure):
        _state = const AuthUnauthenticated();
        notifyListeners();
        return failure.message;
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _repo.logout();
    clearSession();
  }

  /// Pass 14 (FR-DEL-011): permanently delete the signed-in account.
  /// Returns `null` on success (session is fully cleared, caller navigates
  /// away) or a user-facing error message when the server refused.
  Future<String?> deleteAccount({String? password}) async {
    final result = await _repo.deleteAccount(password: password);
    switch (result) {
      case Ok():
        clearSession();
        return null;
      case Err(:final failure):
        return failure.message.isNotEmpty
            ? failure.message
            : 'Could not delete the account. Please try again.';
    }
  }

  void clearSession() {
    // B10: close realtime socket on logout (no-op in mock).
    RealtimeService.instance.disconnect();
    _session = null;
    _state = const AuthUnauthenticated();
    _avatarBytes = null;
    notifyListeners();
    // Clear persisted avatar on logout — fire-and-forget.
    AuthStorageService.instance.clearAvatarBytes();
    // Clear SWR response cache so a new account never reads cached data.
    ResponseCacheService.instance.clear();
  }

  /// Stores locally-picked avatar bytes in memory, notifies listeners,
  /// and persists to SharedPreferences (up to 200 KB) for cross-restart survival.
  void setAvatarBytes(Uint8List? bytes) {
    _avatarBytes = bytes;
    notifyListeners();
    if (bytes != null) {
      // Fire-and-forget — UI is already updated; storage is best-effort.
      AuthStorageService.instance.saveAvatarBytes(bytes);
    } else {
      AuthStorageService.instance.clearAvatarBytes();
    }
  }

  // ── Profile update ─────────────────────────────────────────────────────────

  /// Human-readable reason the last [updateProfile] call failed (backend
  /// message, e.g. the 422 VACATION_REQUIRES_APPROVAL copy). Null after a
  /// success. Callers that show snackbars read this instead of a bare `false`.
  String? _lastProfileError;
  String? get lastProfileError => _lastProfileError;

  Future<bool> updateProfile(UserModel updated) async {
    final result = await _repo.updateProfile(user: updated);
    switch (result) {
      case Ok(:final value):
        _lastProfileError = null;
        if (_session != null) {
          _session = _session!.copyWith(user: value);
          _state = AuthAuthenticated(session: _session!);
          notifyListeners();
        }
        return true;
      case Err(:final failure):
        _lastProfileError = failure.message;
        return false;
    }
  }

  // ── In-memory user refresh ─────────────────────────────────────────────────

  /// Updates the in-memory user model without a network call.
  ///
  /// Used by settings/profile screens to persist local toggle changes
  /// (vacation mode, default attendance) immediately. Also used by the
  /// group-join flow to inject the newly joined groupId so that
  /// [StudentShell] tab visibility rebuilds without requiring a re-login.
  Future<void> refreshUser(UserModel updated) async {
    if (_session == null) return;
    _session = _session!.copyWith(user: updated);
    _state = AuthAuthenticated(session: _session!);
    notifyListeners();
  }

  /// Re-fetches the authenticated user from the backend (GET /auth/me) and
  /// patches the live session — so server-driven changes (e.g. an admin
  /// approving a vacation request flips isVacationMode ON) appear immediately,
  /// without an app restart. Safe no-op on failure (keeps the current user).
  Future<void> refreshCurrentUser() async {
    final user = currentUser;
    if (user == null) return;
    final result = await _repo.getProfile(userId: user.id);
    if (result case Ok(:final value)) {
      await refreshUser(value);
    }
  }

  /// Refreshes the JWT using the stored refresh token so server-side claim
  /// changes (e.g. organizationId set on first group join — the backend
  /// re-reads the user when refreshing) enter the active session. Without this
  /// the access token keeps organizationId=null and org-scoped queries
  /// (group / weekly menu / dashboard) fail. No-op if unauthenticated.
  Future<void> refreshSession() async {
    final token = _session?.refreshToken;
    if (token == null || token.isEmpty) return;
    final result = await _repo.refreshToken(token: token);
    switch (result) {
      case Ok(:final value):
        _session = value;
        _state = AuthAuthenticated(session: value);
        notifyListeners();
      case Err():
        break; // keep current session; user can re-login if it persists
    }
  }
}

// ── InheritedNotifier scope ────────────────────────────────────────────────────

/// Provides [AuthProvider] to the subtree.
///
/// Usage in build:
/// ```dart
/// final auth = AuthProviderScope.of(context);
/// ```
class AuthProviderScope extends InheritedNotifier<AuthProvider> {
  const AuthProviderScope({
    super.key,
    required AuthProvider provider,
    required super.child,
  }) : super(notifier: provider);

  static AuthProvider of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AuthProviderScope>();
    assert(scope != null, 'AuthProviderScope not found in widget tree');
    return scope!.notifier!;
  }

  @override
  bool updateShouldNotify(AuthProviderScope oldWidget) => true;
}

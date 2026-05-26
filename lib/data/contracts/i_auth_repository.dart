import 'package:smart_meal_management/features/auth/models/auth_session.dart';
import 'package:smart_meal_management/features/auth/services/auth_storage_service.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Abstract contract for authentication operations.
///
/// All methods return [Result<T>] — never throw.
/// Designed for future NestJS / JWT backend integration.
abstract interface class IAuthRepository {
  // ── Login ──────────────────────────────────────────────────────────────────

  /// Authenticate with email-or-mobile [identifier] + [password].
  ///
  /// [roleContext] is one of `'student'`, `'admin'`, `'event'` — used to
  /// validate that the credential belongs to the expected role group.
  Future<Result<AuthSession>> login({
    required String identifier,
    required String password,
    required String roleContext,
  });

  // ── OTP ────────────────────────────────────────────────────────────────────

  /// Request a one-time password to be sent to [identifier].
  Future<Result<Unit>> requestOtp({required String identifier});

  /// Verify [otp] sent to [identifier].
  ///
  /// Returns an [AuthSession] on success.
  Future<Result<AuthSession>> verifyOtp({
    required String identifier,
    required String otp,
    required String roleContext,
  });

  // ── Signup ─────────────────────────────────────────────────────────────────

  /// Create a new account.
  ///
  /// For event admin signups pass [eventName], [eventType], [eventDate],
  /// [expectedGuestCount], [autoDeleteEvent]. All other fields are required
  /// for all role types.
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
  });

  // ── Session ────────────────────────────────────────────────────────────────

  /// Clear the current session (server-side revocation + local clear).
  Future<Result<Unit>> logout();

  /// Exchange a refresh token for a new [AuthSession].
  Future<Result<AuthSession>> refreshToken({required String token});

  // ── Profile ────────────────────────────────────────────────────────────────

  /// Load the full profile for [userId].
  Future<Result<UserModel>> getProfile({required String userId});

  /// Persist updated profile fields to the backend.
  Future<Result<UserModel>> updateProfile({required UserModel user});

  /// Attempt to restore a persisted session from secure storage.
  /// Returns [Ok(null)] when no session is stored.
  Future<Result<AuthSession?>> restoreSession();
}

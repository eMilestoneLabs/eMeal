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
  ///
  /// [purpose] selects the backend flow: `'login'` (Email OTP login),
  /// `'signup'` (email verification) or `'reset'` (password recovery →
  /// routed to `/auth/forgot-password`, email-only per AUTH-017).
  Future<Result<Unit>> requestOtp({
    required String identifier,
    String purpose = 'login',
    String? roleContext,
  });

  /// Verify [otp] sent to [identifier].
  ///
  /// [purpose] must match the request (`'login'` | `'signup'`) so the backend
  /// finds the correct OTP record. Returns an [AuthSession] on success.
  Future<Result<AuthSession>> verifyOtp({
    required String identifier,
    required String otp,
    required String roleContext,
    String purpose = 'login',
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
    // Admin: organization name (creates the org on signup).
    String? organizationName,
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

  /// Pass 14 (FR-DEL-011): permanently delete the signed-in account.
  /// The backend revokes every session, soft-removes memberships and
  /// anonymizes PII; attendance/billing history is retained per policy.
  /// [password] is required for accounts that have one.
  Future<Result<Unit>> deleteAccount({String? password});

  // ── Profile ────────────────────────────────────────────────────────────────

  /// Load the full profile for [userId].
  Future<Result<UserModel>> getProfile({required String userId});

  /// Persist updated profile fields to the backend.
  Future<Result<UserModel>> updateProfile({required UserModel user});

  /// Attempt to restore a persisted session from secure storage.
  /// Returns [Ok(null)] when no session is stored.
  Future<Result<AuthSession?>> restoreSession();
}

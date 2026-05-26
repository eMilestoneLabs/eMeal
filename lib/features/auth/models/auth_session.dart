import 'package:equatable/equatable.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Represents an authenticated session returned by the NestJS backend.
///
/// Encapsulates the JWT access token, refresh token, their expiry, and the
/// authenticated [UserModel].  Persisted to secure storage on login and
/// cleared on logout.
///
/// The backend (NestJS + JWT strategy) returns this shape on `/auth/login`
/// and `/auth/refresh`:
/// ```json
/// {
///   "accessToken": "eyJhbGci...",
///   "refreshToken": "dXNlcjox...",
///   "expiresIn": 900,
///   "tokenType": "Bearer",
///   "user": { ... }
/// }
/// ```
class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  /// Short-lived JWT access token. Attached to every API request as
  /// `Authorization: Bearer <accessToken>`.
  final String accessToken;

  /// Long-lived refresh token. Used by [AuthProvider] to silently obtain a new
  /// [accessToken] when the current one is about to expire.
  final String refreshToken;

  /// UTC timestamp when [accessToken] expires.
  /// Derived from the `expiresIn` seconds returned by the backend.
  final DateTime expiresAt;

  /// The full user profile associated with this session.
  final UserModel user;

  // ── Status helpers ─────────────────────────────────────────────────────────

  /// True if [accessToken] is past its [expiresAt] timestamp.
  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// True if [accessToken] will expire within the next 5 minutes.
  ///
  /// Used by the Dio auth interceptor to proactively refresh before the token
  /// actually expires, avoiding a 401 on in-flight requests.
  bool get isExpiringSoon {
    final now = DateTime.now().toUtc();
    final remaining = expiresAt.difference(now);
    return remaining.inSeconds < 300; // < 5 minutes
  }

  /// True when the session has a valid, non-expired access token.
  bool get isValid => !isExpired;

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Deserialise from the NestJS `/auth/login` or `/auth/refresh` JSON body.
  ///
  /// The `expiresIn` field is in seconds; we convert to an absolute [DateTime].
  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final expiresIn = (json['expiresIn'] as num?)?.toInt() ?? 900;
    final expiresAt = json.containsKey('expiresAt')
        ? DateTime.parse(json['expiresAt'] as String)
        : DateTime.now().toUtc().add(Duration(seconds: expiresIn));

    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      expiresAt: expiresAt,
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  /// Serialise to JSON for secure storage persistence.
  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
        'user': user.toJson(),
      };

  // ── CopyWith ───────────────────────────────────────────────────────────────

  AuthSession copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    UserModel? user,
  }) {
    return AuthSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      user: user ?? this.user,
    );
  }

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresAt, user];
}

// ── Auth status ────────────────────────────────────────────────────────────────

/// The lifecycle state of the authentication session.
///
/// Used by [AuthProvider] to drive GoRouter redirects and conditional UI.
enum AuthStatus {
  /// Initial state — [AuthProvider.initialize] has not completed yet.
  /// The app shows the splash/loading screen.
  unknown,

  /// A valid, non-expired [AuthSession] is loaded.
  authenticated,

  /// No session exists, or the session has been cleared after logout.
  unauthenticated,
}

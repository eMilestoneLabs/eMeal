import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_meal_management/features/auth/models/auth_session.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

// ── AuthStorageService ─────────────────────────────────────────────────────────

/// Handles persistence of [AuthSession] and user preferences.
///
/// ## Storage split
///
/// | Data                        | Store                   | Reason                          |
/// |-----------------------------|-------------------------|---------------------------------|
/// | `accessToken`               | FlutterSecureStorage    | Sensitive JWT credential        |
/// | `refreshToken`              | FlutterSecureStorage    | Sensitive long-lived credential |
/// | `expiresAt` (ISO-8601)      | FlutterSecureStorage    | Leaks session lifetime          |
/// | `user` JSON (profile)       | SharedPreferences       | Non-sensitive profile data      |
/// | Login preference            | SharedPreferences       | Non-sensitive UX setting        |
/// | Remembered identifier       | SharedPreferences       | Non-sensitive convenience data  |
///
/// The secure storage keys hold real JWT tokens signed by the NestJS auth service.
class AuthStorageService {
  AuthStorageService._();
  static final AuthStorageService instance = AuthStorageService._();

  // ── Secure storage (tokens) ───────────────────────────────────────────────

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _keyAccessToken = 'secure_access_token';
  static const _keyRefreshToken = 'secure_refresh_token';
  static const _keyExpiresAt = 'secure_expires_at';

  // ── SharedPreferences (non-sensitive metadata) ────────────────────────────

  static const _keyUserJson = 'auth_user_json';
  static const _keyLoginPreference = 'auth_login_preference';
  static const _keyRememberedIdentifier = 'auth_remembered_identifier';
  static const _keyAvatarBase64 = 'auth_avatar_base64';

  /// Maximum avatar size (bytes) eligible for SharedPreferences persistence.
  /// Matches the 200 KB combined image budget from the PRD.
  static const _maxAvatarBytes = 200 * 1024;

  // ── Session ───────────────────────────────────────────────────────────────

  /// Persists [session]:
  ///   - Tokens + expiry → [FlutterSecureStorage] (encrypted on device).
  ///   - User profile    → [SharedPreferences] (non-sensitive).
  Future<void> saveSession(AuthSession session) async {
    // Sensitive fields → secure storage
    await Future.wait([
      _secure.write(key: _keyAccessToken, value: session.accessToken),
      _secure.write(key: _keyRefreshToken, value: session.refreshToken),
      _secure.write(
        key: _keyExpiresAt,
        value: session.expiresAt.toIso8601String(),
      ),
    ]);

    // Non-sensitive user profile → SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUserJson, jsonEncode(session.user.toJson()));
  }

  /// Reconstructs an [AuthSession] from split storage.
  ///
  /// Returns `null` if any required field is missing or the stored data is
  /// corrupted.
  ///
  /// [allowExpired] controls what happens when the *access token* has expired
  /// (the access token lives only ~15 min, while the refresh token is valid for
  /// days). When `false` (default), an expired session is cleared and `null` is
  /// returned — suitable for callers that want a ready-to-use session. When
  /// `true`, the session is returned even with an expired access token so the
  /// Dio refresh flow can mint a new access token from the still-valid refresh
  /// token. The session is NEVER cleared here merely because the access token
  /// expired — only on corruption — so a routine 15-min expiry can no longer
  /// strand the refresh token and force a re-login.
  Future<AuthSession?> loadSession({bool allowExpired = false}) async {
    try {
      // Read tokens from secure storage
      final results = await Future.wait([
        _secure.read(key: _keyAccessToken),
        _secure.read(key: _keyRefreshToken),
        _secure.read(key: _keyExpiresAt),
      ]);

      final accessToken = results[0];
      final refreshToken = results[1];
      final expiresAtRaw = results[2];

      if (accessToken == null || refreshToken == null || expiresAtRaw == null) {
        return null;
      }

      final expiresAt = DateTime.parse(expiresAtRaw);

      // Read user profile from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userRaw = prefs.getString(_keyUserJson);
      if (userRaw == null) return null;

      final user = UserModel.fromJson(
        jsonDecode(userRaw) as Map<String, dynamic>,
      );

      final session = AuthSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        user: user,
      );

      // An expired ACCESS token does not mean the session is dead: the refresh
      // token is still valid for days. Only the explicit non-allowExpired path
      // (callers wanting an immediately-usable token) clears here.
      if (session.isExpired && !allowExpired) {
        await clearSession();
        return null;
      }

      return session;
    } catch (_) {
      // Corrupted data — clear both stores and return null.
      await clearSession();
      return null;
    }
  }

  /// Clears all session data from both secure storage and SharedPreferences.
  Future<void> clearSession() async {
    await Future.wait([
      _secure.delete(key: _keyAccessToken),
      _secure.delete(key: _keyRefreshToken),
      _secure.delete(key: _keyExpiresAt),
    ]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserJson);
    await prefs.remove(_keyAvatarBase64);
  }

  // ── Avatar bytes ───────────────────────────────────────────────────────────

  /// Persists locally-picked avatar [bytes] to SharedPreferences as Base64.
  ///
  /// Silently skips persistence if [bytes] exceeds [_maxAvatarBytes] — the
  /// avatar will still appear in-memory for the current session; only the
  /// cross-restart persistence is skipped. Use backend CDN upload for larger
  /// images (Phase B integration).
  Future<void> saveAvatarBytes(Uint8List bytes) async {
    if (bytes.length > _maxAvatarBytes) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAvatarBase64, base64Encode(bytes));
  }

  /// Loads the persisted avatar bytes, or returns `null` if none stored.
  Future<Uint8List?> loadAvatarBytes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_keyAvatarBase64);
      if (encoded == null || encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  /// Removes the persisted avatar from SharedPreferences.
  Future<void> clearAvatarBytes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAvatarBase64);
  }

  // ── Login preference ──────────────────────────────────────────────────────

  /// Saves whether the user prefers logging in via [email] or [mobile].
  Future<void> saveLoginPreference(LoginPreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLoginPreference, preference.name);
  }

  /// Returns the stored [LoginPreference], defaulting to [LoginPreference.email].
  Future<LoginPreference> loadLoginPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLoginPreference);
    if (raw == null) return LoginPreference.email;
    return LoginPreference.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => LoginPreference.email,
    );
  }

  // ── Remembered identifier ─────────────────────────────────────────────────

  /// Saves the last used email or phone so it can be pre-filled on return.
  Future<void> saveRememberedIdentifier(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRememberedIdentifier, identifier);
  }

  Future<String?> loadRememberedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRememberedIdentifier);
  }

  Future<void> clearRememberedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRememberedIdentifier);
  }
}

// ── LoginPreference ────────────────────────────────────────────────────────────

/// Whether the user prefers to log in using their email or mobile number.
///
/// Stored in SharedPreferences and used to pre-fill the login screen's
/// identifier field and set the keyboard type.
enum LoginPreference {
  email,
  mobile;

  String get label => this == LoginPreference.email ? 'Email' : 'Mobile';
}

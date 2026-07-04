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

  // ── Session-survival fallback (2026-07-04 permanent logout fix) ───────────
  //
  // Android EncryptedSharedPreferences can lose its Keystore master key across
  // APK updates / auto-backup restores on some devices — every secure read
  // then throws forever and the session was being WIPED on that exception,
  // forcing re-login after app updates. The refresh token is therefore also
  // kept as a base64 fallback in plain SharedPreferences (app-private on
  // Android). Deliberate, documented trade-off: refresh tokens rotate on every
  // use, are individually revocable, and reuse trips server-side theft
  // detection — while the keystore-loss failure mode logged users out on
  // every update. Fallback and secure copy are written together and cleared
  // together; the fallback self-heals the secure store when it recovers.
  static const _keyRtFallback = 'auth_rt_fallback';
  static const _keyExpFallback = 'auth_exp_fallback';

  /// Maximum avatar size (bytes) eligible for SharedPreferences persistence.
  /// Matches the 200 KB combined image budget from the PRD.
  static const _maxAvatarBytes = 200 * 1024;

  // ── Session ───────────────────────────────────────────────────────────────

  /// Persists [session]:
  ///   - Tokens + expiry → [FlutterSecureStorage] (encrypted on device).
  ///   - User profile    → [SharedPreferences] (non-sensitive).
  Future<void> saveSession(AuthSession session) async {
    // Fallback + profile FIRST — these must survive even when the Keystore is
    // broken and the secure writes below throw (see _keyRtFallback docs).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyRtFallback,
      base64Encode(utf8.encode(session.refreshToken)),
    );
    await prefs.setString(
      _keyExpFallback,
      session.expiresAt.toIso8601String(),
    );
    await prefs.setString(_keyUserJson, jsonEncode(session.user.toJson()));

    // Sensitive fields → secure storage (primary copy).
    try {
      await Future.wait([
        _secure.write(key: _keyAccessToken, value: session.accessToken),
        _secure.write(key: _keyRefreshToken, value: session.refreshToken),
        _secure.write(
          key: _keyExpiresAt,
          value: session.expiresAt.toIso8601String(),
        ),
      ]);
    } catch (_) {
      // Keystore unavailable — the fallback above carries the session; the
      // next successful saveSession re-seeds the secure store.
    }
  }

  /// Reads all three secure values, retrying briefly — the Android Keystore
  /// can be transiently unavailable right after boot or an app update, and a
  /// transient failure must NEVER destroy the session.
  Future<List<String?>> _secureReadAll() async {
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await Future.wait([
          _secure.read(key: _keyAccessToken),
          _secure.read(key: _keyRefreshToken),
          _secure.read(key: _keyExpiresAt),
        ]);
      } catch (err) {
        lastErr = err;
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
    throw lastErr!;
  }

  /// Best-effort re-seed of the secure store from the fallback copy after the
  /// Keystore recovers (e.g. first launch after an APK update).
  void _reseedSecure(String accessToken, String refreshToken, String? expRaw) {
    Future(() async {
      try {
        await Future.wait([
          _secure.write(key: _keyAccessToken, value: accessToken),
          _secure.write(key: _keyRefreshToken, value: refreshToken),
          if (expRaw != null) _secure.write(key: _keyExpiresAt, value: expRaw),
        ]);
      } catch (_) {
        // Still broken — fallback keeps working; retry on next save.
      }
    });
  }

  /// Minimal profile recovered from the JWT claims when the stored user JSON
  /// is missing (half-restored state). The background /auth/me validation the
  /// app already runs on restore replaces it with the full profile.
  UserModel _skeletonUserFromToken(String accessToken) {
    try {
      final parts = accessToken.split('.');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return UserModel.fromJson({
        'id': payload['sub'] ?? '',
        'name': payload['name'] ?? 'User',
        'email': payload['email'] ?? '',
        'role': payload['role'] ?? 'student',
        'organizationId': payload['organizationId'] ?? '',
      });
    } catch (_) {
      return UserModel.fromJson(const {'id': '', 'name': 'User'});
    }
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
    final prefs = await SharedPreferences.getInstance();

    // 1. Primary: secure storage (with retry — transient Keystore failures
    //    must never look like "no session").
    String? accessToken;
    String? refreshToken;
    String? expiresAtRaw;
    try {
      final results = await _secureReadAll();
      accessToken = results[0];
      refreshToken = results[1];
      expiresAtRaw = results[2];
    } catch (_) {
      // Keystore broken/unavailable — DO NOT clear anything. Fall through to
      // the fallback copy; the pre-fix code wiped the session here, which is
      // exactly what logged users out after every APK update.
    }

    // 2. Fallback: survives Keystore master-key loss across app updates.
    //    An empty access token is fine — it is expired-by-definition and the
    //    Dio refresh flow mints a fresh pair from the refresh token.
    if (refreshToken == null || refreshToken.isEmpty) {
      final fb = prefs.getString(_keyRtFallback);
      if (fb != null && fb.isNotEmpty) {
        try {
          refreshToken = utf8.decode(base64Decode(fb));
          accessToken ??= '';
          expiresAtRaw ??= prefs.getString(_keyExpFallback);
          // Self-heal the secure store in the background.
          _reseedSecure(accessToken, refreshToken, expiresAtRaw);
        } catch (_) {
          // Unreadable fallback — ignore; primary already failed too.
        }
      }
    }

    // Without a refresh token there is genuinely no session to restore.
    if (refreshToken == null || refreshToken.isEmpty) return null;
    accessToken ??= '';

    // Tolerant expiry parse: an unparseable value means "treat the access
    // token as expired and let the refresh flow fix it" — never corruption.
    final expiresAt = DateTime.tryParse(expiresAtRaw ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    // 3. Profile: stored JSON, or a JWT-claims skeleton when the JSON half of
    //    the split storage was lost (background /auth/me re-fills it).
    UserModel user;
    try {
      final userRaw = prefs.getString(_keyUserJson);
      user = userRaw != null
          ? UserModel.fromJson(jsonDecode(userRaw) as Map<String, dynamic>)
          : _skeletonUserFromToken(accessToken);
    } catch (_) {
      user = _skeletonUserFromToken(accessToken);
    }

    final session = AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      user: user,
    );

    // An expired ACCESS token does not mean the session is dead: the refresh
    // token is still valid for days. Callers wanting a ready-to-use token get
    // null, but storage is NEVER cleared here — the pre-fix clearSession()
    // on this path let a routine 15-min expiry (e.g. the realtime socket
    // reconnecting after backgrounding) destroy the refresh token.
    if (session.isExpired && !allowExpired) return null;

    return session;
  }

  /// Clears all session data from both secure storage and SharedPreferences.
  /// Called ONLY on explicit logout, account deletion, or a server-confirmed
  /// token rejection — never on transient storage errors.
  Future<void> clearSession() async {
    try {
      await Future.wait([
        _secure.delete(key: _keyAccessToken),
        _secure.delete(key: _keyRefreshToken),
        _secure.delete(key: _keyExpiresAt),
      ]);
    } catch (_) {
      // A broken Keystore must not block clearing the fallback copy below.
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRtFallback);
    await prefs.remove(_keyExpFallback);
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

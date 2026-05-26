import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Mock authentication service for the MVP development phase.
///
/// Supports login via email OR mobile number.
///
/// ## Seeded test credentials
///
/// | Identifier          | Mobile      | Password     | Role              |
/// |---------------------|-------------|--------------|-------------------|
/// | student@test.com    | 9000000001  | Student@123  | student           |
/// | admin@test.com      | 9000000002  | Admin@123    | hostelAdmin       |
/// | event@test.com      | 9000000003  | Event@123    | eventAdmin        |
/// | manager@test.com    | 9000000004  | Manager@123  | messManager       |
/// | (legacy) admin@mealattend.com | —   | Admin@123    | hostelAdmin       |
/// | (legacy) student@mealattend.com | — | Student@123 | student           |
///
/// Newly signed-up users are registered via [registerSignupCredentials] and
/// can be re-authenticated for the remainder of the app session.
///
/// Replace with real NestJS API calls in production.
abstract final class MockAuthService {
  // ── User fixtures ──────────────────────────────────────────────────────────

  static const _studentUser = UserModel(
    id: 'usr_stu_001',
    name: 'Priya Verma',
    email: 'student@test.com',
    role: UserRole.student,
    organizationId: 'org_001',
    groupId: 'grp_001',
    groupIds: ['grp_001'],
    phone: '9000000001',
    isActive: true,
  );

  static const _adminUser = UserModel(
    id: 'usr_admin_001',
    name: 'Arjun Sharma',
    email: 'admin@test.com',
    role: UserRole.hostelAdmin,
    organizationId: 'org_001',
    phone: '9000000002',
    isActive: true,
  );

  static const _eventAdminUser = UserModel(
    id: 'usr_event_001',
    name: 'Rahul Mahanta',
    email: 'event@test.com',
    role: UserRole.eventAdmin,
    organizationId: 'org_event_001',
    phone: '9000000003',
    isActive: true,
  );

  static const _messManagerUser = UserModel(
    id: 'usr_mgr_001',
    name: 'Sunita Patel',
    email: 'manager@test.com',
    role: UserRole.messManager,
    organizationId: 'org_001',
    phone: '9000000004',
    isActive: true,
  );

  // ── Seeded credential map (immutable baseline) ─────────────────────────────
  // Key: lowercase email OR 10-digit mobile string

  static const Map<String, _Creds> _seededCredentials = {
    // ── Primary test credentials ──────────────────────────────────────────
    'student@test.com':  _Creds('Student@123', _studentUser),
    'admin@test.com':    _Creds('Admin@123',   _adminUser),
    'event@test.com':    _Creds('Event@123',   _eventAdminUser),
    'manager@test.com':  _Creds('Manager@123', _messManagerUser),

    // ── Mobile number lookup (10 digits) ──────────────────────────────────
    '9000000001': _Creds('Student@123', _studentUser),
    '9000000002': _Creds('Admin@123',   _adminUser),
    '9000000003': _Creds('Event@123',   _eventAdminUser),
    '9000000004': _Creds('Manager@123', _messManagerUser),

    // ── Legacy aliases (backward compat) ──────────────────────────────────
    'admin@mealattend.com':   _Creds('Admin@123',   _adminUser),
    'student@mealattend.com': _Creds('Student@123', _studentUser),

    // ── Dev shortcuts ─────────────────────────────────────────────────────
    'admin':   _Creds('admin',   _adminUser),
    'student': _Creds('student', _studentUser),
  };

  /// Runtime-mutable store for newly signed-up users.
  ///
  /// Populated by [registerSignupCredentials] so that signed-up users can
  /// re-authenticate after their mock session expires. Cleared on hot-restart.
  ///
  /// In production this map is replaced by the NestJS user database —
  /// its presence here is purely a mock-phase convenience.
  static final Map<String, _Creds> _runtimeCredentials = {};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the [UserModel] if [identifier] (email or mobile) + [password] match.
  ///
  /// Checks [_seededCredentials] first, then [_runtimeCredentials].
  static UserModel? authenticate(String identifier, String password) {
    final key = _normalise(identifier);
    final creds =
        _seededCredentials[key] ?? _runtimeCredentials[key];
    if (creds == null) return null;
    if (creds.password != password) return null;
    return creds.user;
  }

  /// Returns the mock user for [identifier] regardless of password.
  ///
  /// Used by OTP login flow (password not needed).
  static UserModel? findByIdentifier(String identifier) {
    final key = _normalise(identifier);
    return (_seededCredentials[key] ?? _runtimeCredentials[key])?.user;
  }

  /// Registers credentials for a newly signed-up user so they can re-login.
  ///
  /// Called by [AuthRepository.signup] after creating the mock user.
  /// In production this is a no-op — the backend handles credential storage.
  static void registerSignupCredentials({
    required UserModel user,
    required String password,
  }) {
    final emailKey = _normalise(user.email);
    final mobileCreds = _Creds(password, user);

    _runtimeCredentials[emailKey] = mobileCreds;

    if (user.phone != null && user.phone!.isNotEmpty) {
      final mobileKey = _normalise(user.phone!);
      _runtimeCredentials[mobileKey] = mobileCreds;
    }
  }

  /// Creates a new mock [UserModel] for the signup flow.
  ///
  /// In production this would be replaced by the NestJS POST /auth/signup call.
  static UserModel createSignupUser({
    required String id,
    required String name,
    required String email,
    required String phone,
    required UserRole role,
    String organizationId = 'org_new',
  }) {
    return UserModel(
      id: id,
      name: name,
      email: email,
      role: role,
      organizationId: organizationId,
      phone: phone,
      isActive: true,
      createdAt: DateTime.now(),
    );
  }

  /// The well-known test admin user. Used in repositories that need a fixed admin.
  static UserModel get adminUser => _adminUser;

  /// The well-known test student user.
  static UserModel get studentUser => _studentUser;

  /// The well-known test event admin user.
  static UserModel get eventAdminUser => _eventAdminUser;

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Normalise an identifier for map lookup.
  ///
  /// - Emails: lowercase trim
  /// - Phone numbers: keep only digits, take last 10 (strip country code)
  static String _normalise(String raw) {
    final trimmed = raw.trim();
    // If it looks like a phone number (mostly digits / may have + or spaces)
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length >= 10 &&
        RegExp(r'^[\d\s\+\-]+$').hasMatch(trimmed)) {
      return digitsOnly.length > 10
          ? digitsOnly.substring(digitsOnly.length - 10)
          : digitsOnly;
    }
    return trimmed.toLowerCase();
  }
}

class _Creds {
  const _Creds(this.password, this.user);
  final String password;
  final UserModel user;
}

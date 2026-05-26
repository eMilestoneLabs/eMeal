import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Manages the student profile view — wraps [AuthProvider]'s currentUser
/// and exposes derived summary statistics.
///
/// This provider is intentionally lightweight: it delegates actual user
/// mutation (vacation mode, default attendance) to [AuthProvider.refreshUser]
/// via [StudentSettingsProvider], so there is a single source of truth.
class StudentProfileProvider extends ChangeNotifier {
  StudentProfileProvider({required AuthProvider authProvider})
      : _auth = authProvider {
    _auth.addListener(_onAuthChange);
  }

  final AuthProvider _auth;

  // ── Public getters ─────────────────────────────────────────────────────────

  UserModel? get user => _auth.currentUser;

  String get displayName => user?.name ?? '—';
  String get email => user?.email ?? 'No email set';
  String get initials => user?.initials ?? '?';
  bool get hasAvatar =>
      user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty;
  String? get avatarUrl => user?.avatarUrl;

  bool get isVacationMode => user?.isVacationMode ?? false;
  bool get isDefaultAttendance => user?.isDefaultAttendance ?? false;

  int get groupCount => user?.groupIds.length ?? 0;

  // ── Stub attendance summary (replaced by real repo data in Phase E sync) ───

  int get totalPresent => 22;
  int get totalAbsent => 4;
  int get totalSkipped => 2;
  double get attendanceRate {
    final total = totalPresent + totalAbsent + totalSkipped;
    if (total == 0) return 0;
    return totalPresent / total;
  }

  // ── Logout ─────────────────────────────────────────────────────────────────

  Future<void> logout() async => _auth.clearSession();

  // ── Internal ───────────────────────────────────────────────────────────────

  void _onAuthChange() {
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChange);
    super.dispose();
  }
}

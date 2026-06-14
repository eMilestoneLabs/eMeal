import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

/// Manages the student profile view — wraps [AuthProvider]'s currentUser
/// and exposes the LIVE 30-day attendance summary (fetched from the backend).
class StudentProfileProvider extends ChangeNotifier {
  StudentProfileProvider({
    required AuthProvider authProvider,
    AttendanceRepository? attendanceRepo,
  })  : _auth = authProvider,
        _attendanceRepo = attendanceRepo ?? AttendanceRepository() {
    _auth.addListener(_onAuthChange);
  }

  final AuthProvider _auth;
  final AttendanceRepository _attendanceRepo;

  AttendanceSummary? _summary;
  bool _isLoadingSummary = false;

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

  // ── Live 30-day attendance summary (0 until loaded / when no records) ──────

  bool get isLoadingSummary => _isLoadingSummary;
  int get totalPresent => _summary?.presentDays ?? 0;
  int get totalAbsent => _summary?.absentDays ?? 0;
  int get totalSkipped => _summary?.skippedDays ?? 0;
  double get attendanceRate => _summary?.attendanceRate ?? 0;

  /// Fetches the real last-30-days attendance summary for the user's active
  /// group. Leaves totals at 0 when there is no active group/org or no records.
  Future<void> loadSummary() async {
    final u = user;
    final groupId =
        (u != null && u.effectiveGroupIds.isNotEmpty) ? u.effectiveGroupIds.first : null;
    final orgId = u?.organizationId;
    if (u == null || groupId == null || orgId == null || orgId.isEmpty) return;

    _isLoadingSummary = true;
    notifyListeners();

    final now = DateTime.now();
    final result = await _attendanceRepo.getAttendanceSummary(
      userId: u.id,
      groupId: groupId,
      organizationId: orgId,
      from: now.subtract(const Duration(days: 30)),
      to: now,
    );
    switch (result) {
      case Ok(:final value):
        _summary = value;
      case Err():
        break; // keep zeros on failure
    }

    _isLoadingSummary = false;
    notifyListeners();
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

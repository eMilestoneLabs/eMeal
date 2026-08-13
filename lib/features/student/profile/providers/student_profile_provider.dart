import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
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

  /// Is the member on vacation ANYWHERE? — the profile is an ACCOUNT view with
  /// no group context, so its chip has always meant "on vacation", not "on
  /// vacation in the group you happen to be looking at".
  ///
  /// `isVacationMode` alone would silently narrow that to ORG-WIDE leave only,
  /// because a group-scoped approved request now lives on the membership row
  /// instead of the account flag — so a member on group-A leave would lose the
  /// chip they used to see. `vacationScopedGroupIds` (already on the session,
  /// no extra call) restores the original meaning exactly.
  bool get isVacationMode =>
      (user?.isVacationMode ?? false) ||
      (user?.vacationScopedGroupIds?.isNotEmpty ?? false);
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

    // Cache-first (stale-while-revalidate): show the last-known 30-day summary
    // instantly, then refresh below. Best-effort; the fetch always wins.
    final cacheKey = 'profile_summary:$orgId:$groupId:${u.id}';
    if (_summary == null) {
      _isLoadingSummary = true; // sync: loader, never a zeros flash
    }
    _summary ??= await ResponseCacheService.instance.readObject(
        cacheKey, AttendanceSummary.fromJson,
        maxAge: const Duration(hours: 12));
    _isLoadingSummary = _summary == null;
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
        ResponseCacheService.instance.write(cacheKey, value.toJson());
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

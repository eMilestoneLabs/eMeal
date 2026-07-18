import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/guest_repository.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/guest_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';

/// State manager for admin attendance management screen.
///
/// Loads group attendance for a selected date, supports status filtering,
/// and date navigation.
class AdminAttendanceProvider extends ChangeNotifier {
  AdminAttendanceProvider({AttendanceRepository? repo, GuestRepository? guestRepo})
      : _repo = repo ?? AttendanceRepository(),
        _guestRepo = guestRepo ?? GuestRepository();

  final AttendanceRepository _repo;
  final GuestRepository _guestRepo;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _error;
  List<AttendanceModel> _records = [];
  DateTime _selectedDate = DateTime.now();
  AttendanceStatus? _filterStatus;
  // Issue 4: members on vacation, tracked separately from present/absent/pending.
  Set<String> _vacationUserIds = {};
  int _vacationCount = 0;
  // Synthetic onVacation rows (userName snapshot) so the "Vacation" filter can
  // LIST members, not just count them. Never mixed into _records, so present/
  // absent/pending counts stay correct.
  List<AttendanceModel> _vacationRecords = [];

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDate => _selectedDate;
  AttendanceStatus? get filterStatus => _filterStatus;

  List<AttendanceModel> get filteredRecords {
    // The "Vacation" filter lists members on approved vacation for the selected
    // date. They have NO attendance rows (vacation is a separate state, never a
    // per-day onVacation record), so surface the server-computed vacation list
    // here — otherwise the filter would show empty despite Vacation = N.
    if (_filterStatus == AttendanceStatus.onVacation) return _vacationRecords;
    final base = _filterStatus == null
        ? List<AttendanceModel>.of(_records)
        : _records.where((r) => r.status == _filterStatus).toList();
    return _orderRoster(base);
  }

  /// Live-Test-9 ISSUE-4.5 (locked ordering): Admin/Manager rows FIRST, then
  /// members by the time they marked (earliest first); auto-marked rows
  /// (system/auto sources, no member action time that means anything) order
  /// by name; unmarked rows follow, by name. Guests render in their own
  /// section below the roster and are untouched here.
  List<AttendanceModel> _orderRoster(List<AttendanceModel> rows) {
    int band(AttendanceModel r) {
      if (r.isAdminRole) return 0;
      final autoMarked = r.source != null &&
          r.source != 'self' &&
          r.source != 'admin' &&
          r.source != 'request' &&
          r.source != 'verified';
      if (autoMarked) return 2; // auto-attendance → alphabetical
      return r.markedAt != null ? 1 : 3; // marked by time, unmarked last
    }

    rows.sort((a, b) {
      final ba = band(a);
      final bb = band(b);
      if (ba != bb) return ba - bb;
      if (ba == 1) {
        final c = (a.markedAt ?? DateTime(0)).compareTo(
            b.markedAt ?? DateTime(0));
        if (c != 0) return c;
      }
      return (a.userName ?? '')
          .toLowerCase()
          .compareTo((b.userName ?? '').toLowerCase());
    });
    return rows;
  }

  int get totalCount => _records.length;
  int get presentCount =>
      _records.where((r) => r.status == AttendanceStatus.present).length;
  int get absentCount =>
      _records.where((r) => r.status == AttendanceStatus.absent).length;
  int get pendingCount =>
      _records.where((r) => r.status == AttendanceStatus.pending).length;

  // Issue 4: count of members currently on vacation in this group. They are not
  // counted as present/absent/pending — vacation is a separate state.
  int get vacationCount => _vacationCount;
  Set<String> get vacationUserIds => _vacationUserIds;

  // Live-Test-5 (Guest Attendance Visibility policy): hosted guests for the
  // selected date, rendered as a dedicated section BELOW the member list —
  // guests are attendance records, never merged into the member rows.
  List<MealGuestModel> _guests = [];
  List<MealGuestModel> get guests => _guests;

  /// Live-Test-10 (filter mapping, survey-locked): guests follow the active
  /// status filter instead of always rendering in full —
  ///   All → every guest · Present → approved bookings · Absent →
  ///   cancelled/rejected + no-show · Pending → awaiting approval ·
  ///   Skipped / Vacation → none (member-only concepts).
  List<MealGuestModel> get visibleGuests {
    switch (_filterStatus) {
      case null:
        return _guests;
      case AttendanceStatus.present:
        return _guests.where((g) => g.isConfirmed).toList();
      case AttendanceStatus.absent:
        return _guests
            .where((g) => g.isCancelled || g.status == 'no_show')
            .toList();
      case AttendanceStatus.pending:
        return _guests.where((g) => g.isPending).toList();
      case AttendanceStatus.skipped:
      case AttendanceStatus.onVacation:
        return const [];
    }
  }

  /// Confirmed guest meals (booked + fully approved) — the "Hosted Guests"
  /// stat; cancelled/pending rows are listed but not counted here.
  int get confirmedGuestCount => _guests.where((g) => g.isConfirmed).length;

  /// Total Meals = member meals (present) + confirmed guest meals (policy).
  int get totalMealsCount => presentCount + confirmedGuestCount;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load({
    required String groupId,
    required String organizationId,
    bool guestsEnabled = false,
  }) async {
    // Cache-first: paint last-known records instantly, then refresh.
    final cacheKey =
        'admin_attendance:$organizationId:$groupId:${_selectedDate.year}-${_selectedDate.month}-${_selectedDate.day}';
    if (_records.isEmpty) {
      _isLoading = true; // sync: first build shows the loader, never "No records found"
      // Miss-vs-empty aware: a cached EMPTY day (e.g. every morning before
      // anyone marks) paints instantly too; only a true cache MISS keeps the
      // loader while the network fetch below runs.
      final cached = await ResponseCacheService.instance.readListOrNull(
          cacheKey, AttendanceModel.fromJson, maxAge: const Duration(hours: 12));
      if (cached != null) {
        _records = cached;
        _isLoading = false;
      }
    } else {
      _isLoading = false;
    }
    _error = null;
    notifyListeners();

    // Fetch the date-scoped vacation set IN PARALLEL with attendance so the
    // spinner waits for one round-trip, not two. The "Vacation = N" count lands
    // a moment later and updates in place. It reflects members on APPROVED
    // vacation covering the SELECTED DATE (server-computed, slot-aware) — the
    // global isVacationMode flag was date-agnostic and stayed 0 for future or
    // past-dated approvals.
    final vacationFuture = _repo.getGroupVacationMembers(
      groupId: groupId,
      date: _selectedDate,
    );

    // Live-Test-5: hosted-guest rows ride the SAME parallel wave (zero extra
    // latency) — fetched only when the group's guest feature is on.
    final dateStr =
        '${_selectedDate.year.toString().padLeft(4, '0')}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final guestsFuture = guestsEnabled
        ? _guestRepo.listGuests(groupId: groupId, date: dateStr)
        : null;

    final result = await _repo.getGroupAttendance(
      groupId: groupId,
      organizationId: organizationId,
      date: _selectedDate,
    );

    switch (result) {
      case Ok(:final value):
        _records = value;
        ResponseCacheService.instance
            .writeList(cacheKey, value, (r) => r.toJson());
      case Err(:final failure):
        _error = failure.message;
    }

    // Records are in — drop the spinner now; the vacation count updates when its
    // parallel fetch lands below.
    _isLoading = false;
    notifyListeners();

    // Surface a separate "Vacation = X" count. Members on vacation are tracked
    // apart from present/absent/pending (they are not absentees). On failure the
    // count is left untouched rather than reset, so a transient error can't blank
    // a previously-correct number.
    if (guestsFuture != null) {
      final guestsResult = await guestsFuture;
      if (guestsResult case Ok(:final value)) {
        // Live-Test-9 ISSUE-4.5 (locked ordering): guests list by booking
        // time (earliest first); ties fall back to name.
        _guests = List.of(value)
          ..sort((a, b) {
            final c = (a.createdAt ?? DateTime(0))
                .compareTo(b.createdAt ?? DateTime(0));
            if (c != 0) return c;
            return (a.displayName ?? '')
                .toLowerCase()
                .compareTo((b.displayName ?? '').toLowerCase());
          });
        notifyListeners();
      }
    } else if (_guests.isNotEmpty) {
      _guests = [];
      notifyListeners();
    }

    final vacationResult = await vacationFuture;
    if (vacationResult case Ok(:final value)) {
      _vacationUserIds = value.map((m) => m.id).toSet();
      _vacationCount = value.length;
      // Build synthetic rows so the "Vacation" filter lists these members.
      _vacationRecords = value
          .map((m) => AttendanceModel(
                id: 'vac_${m.id}',
                mealId: '',
                userId: m.id,
                groupId: groupId,
                organizationId: organizationId,
                status: AttendanceStatus.onVacation,
                date: _selectedDate,
                userName: m.name,
              ))
          .toList();
      notifyListeners();
    }
  }

  // ── Filters ────────────────────────────────────────────────────────────────

  void setFilter(AttendanceStatus? status) {
    _filterStatus = status;
    notifyListeners();
  }

  void setDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  // SRS Module 03 ATT-004: the admin override write path was REMOVED —
  // attendance ownership belongs to the member; post-window changes flow
  // exclusively through the Correction Request approve/reject workflow.

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

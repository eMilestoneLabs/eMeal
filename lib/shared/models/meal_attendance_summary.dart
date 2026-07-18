/// Per-meal attendance + preference summary for the admin dashboard.
///
/// Mirrors the backend `GET /attendance/meal-summary` response
/// (MealAttendanceSummarySerializer — CONTRACT-LOCKED):
///   { mealId, slotKey, mealName, date, totalMembers,
///     presentDays, absentDays, skippedDays, preferenceBreakdown:{tag:count} }
///
/// This is the source of truth for **meal-wise** dashboard numbers: each meal
/// slot carries its OWN present/absent/skipped counts and its OWN preference
/// breakdown, so admins see "how much food per meal" rather than a combined
/// daily total. Reuses the existing endpoint — no new backend contract.
class MealAttendanceSummary {
  const MealAttendanceSummary({
    required this.mealId,
    required this.slotKey,
    required this.mealName,
    required this.date,
    required this.totalMembers,
    required this.presentCount,
    required this.absentCount,
    required this.skippedCount,
    required this.preferenceBreakdown,
    this.snapshotPrice,
    this.guestCount = 0,
    this.guestAdults = 0,
    this.guestChildren = 0,
    this.attendingTotal,
    this.guestPreferenceBreakdown = const {},
    this.expectedParticipants,
    this.preferenceGroupBreakdown = const {},
    this.vacationCount = 0,
    this.pendingCount,
    this.guestPreferenceGroupBreakdown = const {},
    this.guestPendingApproval = 0,
    this.guestCancelled = 0,
    this.guestNoShow = 0,
    this.guestTotalRequests = 0,
  });

  final String mealId;
  final String slotKey;
  final String mealName;
  final String date;
  final int totalMembers;
  final int presentCount;
  final int absentCount;
  final int skippedCount;

  /// Issue 1: snapshot unit price actually billed for present records on this
  /// meal+date (null when pricing is off or nobody marked present). The admin
  /// dashboard prefers this over the live Meal.price so a later price edit on a
  /// closed meal never rewrites what today already showed.
  final int? snapshotPrice;

  /// tag -> count for THIS meal only (e.g. {"veg":12,"chicken":8}).
  final Map<String, int> preferenceBreakdown;

  /// Module 22 (FR-HG-060/061, Pass 9): hosted-guest plates for this meal —
  /// booked + approved guests only, itemised separately from members.
  final int guestCount;
  final int guestAdults;
  final int guestChildren;

  /// present members + confirmed guests — the kitchen's real plate count.
  /// Null on cached payloads from pre-guest app builds.
  final int? attendingTotal;

  /// tag -> count for GUEST plates only (e.g. {"veg":2,"unspecified":1}).
  final Map<String, int> guestPreferenceBreakdown;

  /// Pass 15 (FR-ANL-003): expected participants = active, non-blocked,
  /// non-vacation members for this meal/date. Null on cached payloads from
  /// pre-Pass-15 app builds (falls back to [totalMembers] where shown).
  final int? expectedParticipants;

  /// Module 36 (FR-PG-050): multi-preference-group selections of PRESENT
  /// members, keyed by snapshotted labels:
  /// {"Roti/Rice": {"Roti": 4, "Rice": 2}}. Empty for groups using only the
  /// legacy flat preference and on cached pre-fix payloads (additive).
  final Map<String, Map<String, int>> preferenceGroupBreakdown;

  /// Live-Test-9 ISSUE-4.2: members covered by vacation for this meal/date.
  final int vacationCount;

  /// Live-Test-9 ISSUE-4.2: LIVE no-response count while the window is open
  /// (expected − present − absent − skipped; reaches 0 once the close sweep
  /// materializes System Skip). Null on cached pre-fix payloads.
  final int? pendingCount;

  /// Live-Test-9 ISSUE-4.3: GUEST preference-group plate counts, keyed by
  /// snapshotted labels — every group a guest selected counts (the flat
  /// [guestPreferenceBreakdown] only carries the derived primary tag).
  final Map<String, Map<String, int>> guestPreferenceGroupBreakdown;

  /// Live-Test-10 Kitchen Summary (additive): administrative guest-request
  /// statuses. Only [guestCount] (approved bookings) feeds kitchen, billing
  /// and attendance totals — these are dashboard visibility rows. All default
  /// to 0 on cached pre-fix payloads.
  final int guestPendingApproval;
  final int guestCancelled;
  final int guestNoShow;
  final int guestTotalRequests;

  /// Total plates to cook: present members + confirmed guests.
  int get effectiveAttendingTotal => attendingTotal ?? (presentCount + guestCount);

  static Map<String, int> _breakdown(dynamic raw) {
    final out = <String, int>{};
    ((raw as Map?) ?? const {}).forEach((k, v) {
      final n = v is int ? v : int.tryParse(v.toString()) ?? 0;
      if (n > 0) out[k.toString()] = n;
    });
    return out;
  }

  static Map<String, Map<String, int>> _nestedBreakdown(dynamic raw) {
    final out = <String, Map<String, int>>{};
    ((raw as Map?) ?? const {}).forEach((k, v) {
      final inner = _breakdown(v);
      if (inner.isNotEmpty) out[k.toString()] = inner;
    });
    return out;
  }

  factory MealAttendanceSummary.fromJson(Map<String, dynamic> j) {
    final breakdown = _breakdown(j['preferenceBreakdown']);
    return MealAttendanceSummary(
      mealId: (j['mealId'] ?? '').toString(),
      slotKey: (j['slotKey'] ?? '').toString(),
      mealName: (j['mealName'] ?? '').toString(),
      date: (j['date'] ?? '').toString(),
      totalMembers: j['totalMembers'] ?? 0,
      // Backend uses presentDays/absentDays/skippedDays naming (count fields).
      presentCount: j['presentDays'] ?? j['presentCount'] ?? 0,
      absentCount: j['absentDays'] ?? j['absentCount'] ?? 0,
      skippedCount: j['skippedDays'] ?? j['skippedCount'] ?? 0,
      snapshotPrice: j['snapshotPrice'] is int
          ? j['snapshotPrice'] as int
          : (j['snapshotPrice'] == null
              ? null
              : int.tryParse(j['snapshotPrice'].toString())),
      preferenceBreakdown: breakdown,
      guestCount: j['guestCount'] is int
          ? j['guestCount'] as int
          : int.tryParse(j['guestCount']?.toString() ?? '') ?? 0,
      guestAdults: j['guestAdults'] is int
          ? j['guestAdults'] as int
          : int.tryParse(j['guestAdults']?.toString() ?? '') ?? 0,
      guestChildren: j['guestChildren'] is int
          ? j['guestChildren'] as int
          : int.tryParse(j['guestChildren']?.toString() ?? '') ?? 0,
      attendingTotal: j['attendingTotal'] is int
          ? j['attendingTotal'] as int
          : int.tryParse(j['attendingTotal']?.toString() ?? ''),
      guestPreferenceBreakdown: _breakdown(j['guestPreferenceBreakdown']),
      expectedParticipants: j['expectedParticipants'] is int
          ? j['expectedParticipants'] as int
          : int.tryParse(j['expectedParticipants']?.toString() ?? ''),
      preferenceGroupBreakdown: _nestedBreakdown(j['preferenceGroupBreakdown']),
      vacationCount: j['vacationCount'] is int
          ? j['vacationCount'] as int
          : int.tryParse(j['vacationCount']?.toString() ?? '') ?? 0,
      pendingCount: j['pendingCount'] is int
          ? j['pendingCount'] as int
          : int.tryParse(j['pendingCount']?.toString() ?? ''),
      guestPreferenceGroupBreakdown:
          _nestedBreakdown(j['guestPreferenceGroupBreakdown']),
      guestPendingApproval: _asInt(j['guestPendingApproval']),
      guestCancelled: _asInt(j['guestCancelled']),
      guestNoShow: _asInt(j['guestNoShow']),
      guestTotalRequests: _asInt(j['guestTotalRequests']),
    );
  }

  /// Tolerant int parse — 0 on null/garbage (cached pre-fix payloads).
  static int _asInt(dynamic v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  /// Round-trip serializer for the local response cache (cache-first paint).
  /// Emits the backend field names so [fromJson] parses it back unchanged.
  Map<String, dynamic> toJson() => {
        'mealId': mealId,
        'slotKey': slotKey,
        'mealName': mealName,
        'date': date,
        'totalMembers': totalMembers,
        'presentDays': presentCount,
        'absentDays': absentCount,
        'skippedDays': skippedCount,
        'snapshotPrice': snapshotPrice,
        'preferenceBreakdown': preferenceBreakdown,
        'guestCount': guestCount,
        'guestAdults': guestAdults,
        'guestChildren': guestChildren,
        'attendingTotal': attendingTotal,
        'guestPreferenceBreakdown': guestPreferenceBreakdown,
        'expectedParticipants': expectedParticipants,
        'preferenceGroupBreakdown': preferenceGroupBreakdown,
        'vacationCount': vacationCount,
        'pendingCount': pendingCount,
        'guestPreferenceGroupBreakdown': guestPreferenceGroupBreakdown,
        'guestPendingApproval': guestPendingApproval,
        'guestCancelled': guestCancelled,
        'guestNoShow': guestNoShow,
        'guestTotalRequests': guestTotalRequests,
      };
}

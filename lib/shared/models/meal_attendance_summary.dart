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
    );
  }

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
      };
}

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
  });

  final String mealId;
  final String slotKey;
  final String mealName;
  final String date;
  final int totalMembers;
  final int presentCount;
  final int absentCount;
  final int skippedCount;

  /// tag -> count for THIS meal only (e.g. {"veg":12,"chicken":8}).
  final Map<String, int> preferenceBreakdown;

  factory MealAttendanceSummary.fromJson(Map<String, dynamic> j) {
    final raw = (j['preferenceBreakdown'] as Map?) ?? const {};
    final breakdown = <String, int>{};
    raw.forEach((k, v) {
      final n = v is int ? v : int.tryParse(v.toString()) ?? 0;
      if (n > 0) breakdown[k.toString()] = n;
    });
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
      preferenceBreakdown: breakdown,
    );
  }
}

/// Issue 3 — vacation approval workflow request.
///
/// Mirrors the backend VacationRequest serializer contract:
/// startDate / endDate are date-only (YYYY-MM-DD); review timestamps are
/// ISO-8601 or null; status is one of pending | approved | rejected | cancelled.
class VacationRequestModel {
  const VacationRequestModel({
    required this.id,
    required this.organizationId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.groupId,
    this.userName,
    this.reason,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.createdAt,
    this.updatedAt,
    this.startSlotKey,
    this.endSlotKey,
    this.conflicts = const [],
  });

  final String id;
  final String organizationId;
  final String? groupId;
  final String userId;
  final String? userName;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Pass 11 (FR-VACX-003): optional meal-granular boundaries — on the start
  /// date coverage begins at this slot; on the end date it ends at this slot.
  /// Null = whole boundary day covered.
  final String? startSlotKey;
  final String? endSlotKey;

  /// Pass 11 (FR-VACX-004 / LOOP-046): present only on the APPROVE response —
  /// days the member explicitly marked Present inside the approved range.
  /// Those marks are KEPT (and billed); each item: {date, mealId, mealName}.
  final List<VacationConflict> conflicts;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';

  /// FR-VACX-003 — exact Dart mirror of the server's `requestCoversMeal`
  /// boundary math (vacation-coverage.util.ts): on the start date only meals
  /// opening AT/AFTER the startSlotKey meal's open time are covered; on the
  /// end date only meals opening AT/BEFORE the endSlotKey meal's open time;
  /// interior days are fully covered. Unknown open times resolve to COVERED
  /// (fail-safe — coverage only ever suppresses marking, never forces it).
  /// [day] is compared by calendar date components only.
  bool coversMealOn(
    DateTime day, {
    required int? mealOpenMinutes,
    required int? Function(String slotKey) slotOpenMinutes,
    // ISSUE-005: slotKey of the meal being evaluated — identity-first
    // boundary coverage (mirror of the server's mealSlotKey parameter).
    String? mealSlotKey,
  }) {
    DateTime d(DateTime x) => DateTime.utc(x.year, x.month, x.day);
    final t = d(day);
    final start = d(startDate);
    final end = d(endDate);
    if (t.isBefore(start) || t.isAfter(end)) return false;

    final isStartDay = t == start;
    final isEndDay = t == end;
    if ((!isStartDay || startSlotKey == null) &&
        (!isEndDay || endSlotKey == null)) {
      return true; // interior day, or boundary day without a slot bound
    }

    // ISSUE-005: the boundary meal itself is covered by IDENTITY — the start
    // meal is always the first covered meal and the end meal the last, even
    // when per-day window overrides shift its clock (server mirror).
    if (mealSlotKey != null) {
      final startIdentity = isStartDay && startSlotKey == mealSlotKey;
      final endIdentity = isEndDay && endSlotKey == mealSlotKey;
      if (startIdentity && (!isEndDay || endSlotKey == null || endIdentity)) {
        return true;
      }
      if (endIdentity && (!isStartDay || startSlotKey == null || startIdentity)) {
        return true;
      }
    }

    if (mealOpenMinutes == null) return true; // windowless meal → fail-safe

    if (isStartDay && startSlotKey != null) {
      final bound = slotOpenMinutes(startSlotKey!);
      if (bound != null && mealOpenMinutes < bound) {
        return false; // before vacation starts
      }
    }
    if (isEndDay && endSlotKey != null) {
      final bound = slotOpenMinutes(endSlotKey!);
      if (bound != null && mealOpenMinutes > bound) {
        return false; // after vacation ends
      }
    }
    return true;
  }

  static DateTime _parseDate(dynamic v) {
    if (v == null) return DateTime.now();
    final s = v.toString();
    // date-only 'YYYY-MM-DD' or full ISO
    return DateTime.tryParse(s.length == 10 ? '${s}T00:00:00' : s) ??
        DateTime.now();
  }

  static DateTime? _parseNullable(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  factory VacationRequestModel.fromJson(Map<String, dynamic> j) {
    return VacationRequestModel(
      id: (j['id'] ?? '').toString(),
      organizationId: (j['organizationId'] ?? '').toString(),
      groupId: j['groupId']?.toString(),
      userId: (j['userId'] ?? '').toString(),
      userName: j['userName']?.toString(),
      startDate: _parseDate(j['startDate']),
      endDate: _parseDate(j['endDate']),
      reason: j['reason']?.toString(),
      status: (j['status'] ?? 'pending').toString(),
      reviewedBy: j['reviewedBy']?.toString(),
      reviewedAt: _parseNullable(j['reviewedAt']),
      reviewNote: j['reviewNote']?.toString(),
      createdAt: _parseNullable(j['createdAt']),
      updatedAt: _parseNullable(j['updatedAt']),
      startSlotKey: j['startSlotKey']?.toString(),
      endSlotKey: j['endSlotKey']?.toString(),
      conflicts: (j['conflicts'] is List)
          ? (j['conflicts'] as List)
              .whereType<Map<String, dynamic>>()
              .map(VacationConflict.fromJson)
              .toList()
          : const [],
    );
  }
}

/// A kept-Present conflict surfaced when approving an overlapping vacation.
class VacationConflict {
  const VacationConflict({
    required this.date,
    required this.mealName,
    this.mealId,
  });

  final String date; // YYYY-MM-DD
  final String? mealId;
  final String mealName;

  factory VacationConflict.fromJson(Map<String, dynamic> j) =>
      VacationConflict(
        date: (j['date'] ?? '').toString(),
        mealId: j['mealId']?.toString(),
        mealName: (j['mealName'] ?? 'Meal').toString(),
      );
}

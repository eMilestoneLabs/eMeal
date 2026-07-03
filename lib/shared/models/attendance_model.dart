import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';

enum AttendanceStatus { pending, present, absent, skipped, onVacation }

@immutable
class MealAttendanceWindow {
  const MealAttendanceWindow({required this.openTime, required this.closeTime});
  final String openTime;   // "HH:mm"
  final String closeTime;  // "HH:mm"
  factory MealAttendanceWindow.fromJson(Map<String, dynamic> j) =>
      MealAttendanceWindow(
        openTime: j['openTime'] ?? '00:00',
        closeTime: j['closeTime'] ?? '23:59',
      );
  Map<String, dynamic> toJson() => {
        'openTime': openTime,
        'closeTime': closeTime,
      };
}

@immutable
class AttendanceModel {
  const AttendanceModel({
    required this.id,
    required this.mealId,
    required this.userId,
    required this.groupId,
    required this.organizationId,
    required this.status,
    required this.date,
    this.markedAt,
    this.preference,
    this.note,
    this.mealName,
    this.userName,
    this.userPhone,
    this.price,
    this.selections,
    this.preferences,
    this.source,
  });

  final String id;
  final String mealId;
  final String userId;
  final String groupId;
  final String organizationId;
  final AttendanceStatus status;
  final DateTime date;
  final DateTime? markedAt;
  final String? preference;
  final String? note;
  final String? mealName;

  /// Joined member display name (admin-facing lists/exports). Null for a
  /// student's own records. Issues #4/#7/#11.
  final String? userName;

  /// Joined member phone (admin-facing). Null when not included.
  final String? userPhone;

  /// Additive: ₹ price snapshot at mark time (per-day override or master).
  /// Null for pre-pricing records — billing falls back to the master meal price.
  final int? price;

  /// Module 36 (FR-PG-031): outgoing multi-group selection set — sent with
  /// Present marks on meals that carry explicit preference groups.
  final List<PreferenceSelection>? selections;

  /// Module 36 (FR-PG-013): immutable selection snapshot from the backend
  /// ([{groupLabel, optionLabel, quantity, ...}]) — display-only.
  final List<dynamic>? preferences;

  /// SRS FR-TRUST-002/010 (Pass 7): how this record came to exist —
  /// self | default | system_default | admin | request | verified.
  /// Drives the "Auto-marked" badge and change-history display.
  final String? source;

  bool get isSystemDefault => source == 'system_default';

  factory AttendanceModel.fromJson(Map<String, dynamic> j) => AttendanceModel(
        id: j['id'] ?? '',
        mealId: j['mealId'] ?? '',
        userId: j['userId'] ?? '',
        groupId: j['groupId'] ?? '',
        organizationId: j['organizationId'] ?? '',
        status: AttendanceStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => AttendanceStatus.pending,
        ),
        date: j['date'] != null ? DateTime.parse(j['date']) : DateTime.now(),
        // Issue 5: backend stores markedAt in UTC (ISO 'Z'). Convert to the
        // device's local time so every screen (recent activity, history,
        // exports) shows the actual submission time (e.g. 23:00, not 17:30).
        markedAt: j['markedAt'] != null
            ? DateTime.parse(j['markedAt']).toLocal()
            : null,
        preference: j['preference'],
        note: j['note'],
        mealName: j['mealName'],
        userName: j['userName'],
        userPhone: j['userPhone'],
        price: j['price'] is int
            ? j['price'] as int
            : (j['price'] != null
                ? int.tryParse(j['price'].toString())
                : null),
        preferences: j['preferences'] is List
            ? j['preferences'] as List<dynamic>
            : null,
        source: j['source']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mealId': mealId,
        'userId': userId,
        'groupId': groupId,
        'organizationId': organizationId,
        'status': status.name,
        'date': date.toIso8601String(),
        'markedAt': markedAt?.toIso8601String(),
        'preference': preference,
        'note': note,
        'mealName': mealName,
        'userName': userName,
        'userPhone': userPhone,
        'price': price,
        'preferences': preferences,
        'source': source,
      };

  AttendanceModel copyWith({
    AttendanceStatus? status,
    DateTime? markedAt,
    String? preference,
    String? note,
    String? mealName,
    int? price,
    List<PreferenceSelection>? selections,
    List<dynamic>? preferences,
  }) =>
      AttendanceModel(
        id: id,
        mealId: mealId,
        userId: userId,
        groupId: groupId,
        organizationId: organizationId,
        status: status ?? this.status,
        date: date,
        markedAt: markedAt ?? this.markedAt,
        preference: preference ?? this.preference,
        note: note ?? this.note,
        mealName: mealName ?? this.mealName,
        userName: userName,
        userPhone: userPhone,
        price: price ?? this.price,
        selections: selections ?? this.selections,
        preferences: preferences ?? this.preferences,
        source: source,
      );
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
    required this.skippedDays,
    this.vacationDays = 0,
  });

  final int totalDays;
  final int presentDays;
  final int absentDays;
  final int skippedDays;

  /// Additive: excused vacation days in the period — counted separately and
  /// NEVER part of [attendanceRate]'s denominator.
  final int vacationDays;

  /// Attendance rate as a fraction (0.0 – 1.0).
  ///
  /// Uses the total of marked records (present + absent + skipped) as the
  /// denominator rather than [totalDays] (calendar days), because the
  /// repository stores meal-record counts — not day counts — in these fields.
  /// This prevents inflated values like 174% when 3 meals/day are counted.
  double get attendanceRate {
    final total = presentDays + absentDays + skippedDays;
    return total == 0 ? 0.0 : presentDays / total;
  }

  factory AttendanceSummary.fromJson(Map<String, dynamic> j) =>
      AttendanceSummary(
        totalDays: j['totalDays'] ?? 0,
        presentDays: j['presentDays'] ?? 0,
        absentDays: j['absentDays'] ?? 0,
        skippedDays: j['skippedDays'] ?? 0,
        vacationDays: j['vacationDays'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'totalDays': totalDays,
        'presentDays': presentDays,
        'absentDays': absentDays,
        'skippedDays': skippedDays,
        'vacationDays': vacationDays,
      };
}

// ── AttendanceSummary aliases ──────────────────────────────────────────────────
// Screens reference these legacy getter names; keep them as forwards.
extension AttendanceSummaryAliases on AttendanceSummary {
  double get attendancePercent => attendanceRate * 100;
  int get presentCount => presentDays;
  int get absentCount => absentDays;
  int get pendingCount => skippedDays; // skipped treated as pending in UI
}

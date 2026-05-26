import 'package:flutter/foundation.dart';

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
        markedAt:
            j['markedAt'] != null ? DateTime.parse(j['markedAt']) : null,
        preference: j['preference'],
        note: j['note'],
        mealName: j['mealName'],
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
      };

  AttendanceModel copyWith({
    AttendanceStatus? status,
    DateTime? markedAt,
    String? preference,
    String? note,
    String? mealName,
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
      );
}

class AttendanceSummary {
  const AttendanceSummary({
    required this.totalDays,
    required this.presentDays,
    required this.absentDays,
    required this.skippedDays,
  });

  final int totalDays;
  final int presentDays;
  final int absentDays;
  final int skippedDays;

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
      );

  Map<String, dynamic> toJson() => {
        'totalDays': totalDays,
        'presentDays': presentDays,
        'absentDays': absentDays,
        'skippedDays': skippedDays,
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

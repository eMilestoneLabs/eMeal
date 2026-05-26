import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// Static mock attendance records for MVP development.
///
/// Covers all [AttendanceStatus] variants and spans 30 days of history.
abstract final class MockAttendanceData {
  static final _now = DateTime.now();

  static List<AttendanceModel> generate({
    required String userId,
    required String groupId,
    required String organizationId,
    int days = 30,
  }) {
    final records = <AttendanceModel>[];
    final mealIds = ['meal_001', 'meal_002', 'meal_003'];
    final mealNames = ['Breakfast', 'Lunch', 'Dinner'];
    final statuses = [
      AttendanceStatus.present,
      AttendanceStatus.present,
      AttendanceStatus.present,
      AttendanceStatus.absent,
      AttendanceStatus.skipped,
    ];

    // Rotating preference values for present records — seeds analytics.
    const preferences = ['Veg', 'Chicken', 'Veg', 'Fish', 'Veg', 'Egg', 'Jain', 'Chicken'];

    int idCounter = 1;
    // Stop at d=1 (yesterday) so today has no pre-existing records.
    // getTodayAttendance then falls back to todayRecords() which are all
    // pending — allowing the student to actually mark during testing.
    for (int d = days - 1; d >= 1; d--) {
      final date = DateTime(_now.year, _now.month, _now.day - d);
      for (int m = 0; m < mealIds.length; m++) {
        final status = statuses[(idCounter + m) % statuses.length];
        // Seed preference on ~60 % of present records so analytics card renders.
        final pref = (status == AttendanceStatus.present && (idCounter % 5) != 0)
            ? preferences[idCounter % preferences.length]
            : null;
        records.add(AttendanceModel(
          id: 'att_${idCounter++}',
          mealId: mealIds[m],
          userId: userId,
          groupId: groupId,
          organizationId: organizationId,
          status: status,
          date: date,
          markedAt: status != AttendanceStatus.pending
              ? date.add(Duration(hours: 7 + m * 4))
              : null,
          mealName: mealNames[m],
          preference: pref,
        ));
      }
    }
    return records;
  }

  static List<AttendanceModel> todayRecords({
    required String userId,
    required String groupId,
    required String organizationId,
  }) {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return [
      AttendanceModel(
        id: 'att_today_1',
        mealId: 'meal_001',
        userId: userId,
        groupId: groupId,
        organizationId: organizationId,
        status: AttendanceStatus.present,
        date: today,
        markedAt: today.add(const Duration(hours: 7, minutes: 30)),
        mealName: 'Breakfast',
      ),
      AttendanceModel(
        id: 'att_today_2',
        mealId: 'meal_002',
        userId: userId,
        groupId: groupId,
        organizationId: organizationId,
        status: AttendanceStatus.pending,
        date: today,
        mealName: 'Lunch',
      ),
      AttendanceModel(
        id: 'att_today_3',
        mealId: 'meal_003',
        userId: userId,
        groupId: groupId,
        organizationId: organizationId,
        status: AttendanceStatus.pending,
        date: today,
        mealName: 'Dinner',
      ),
    ];
  }

  static AttendanceSummary summary({int days = 30}) {
    final total = days * 3;
    final present = (total * 0.75).round();
    final absent = (total * 0.12).round();
    final skipped = total - present - absent;
    return AttendanceSummary(
      totalDays: days,
      presentDays: present ~/ 3,
      absentDays: absent ~/ 3,
      skippedDays: skipped ~/ 3,
    );
  }
}

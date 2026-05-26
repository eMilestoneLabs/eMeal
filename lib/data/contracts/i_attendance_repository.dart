import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Abstract contract for all attendance-related data operations.
abstract interface class IAttendanceRepository {
  /// Fetch all attendance records for [userId] in [groupId] for today.
  Future<Result<List<AttendanceModel>>> getTodayAttendance({
    required String userId,
    required String groupId,
    required String organizationId,
  });

  /// Fetch attendance summary (present/absent/skipped counts) for a date range.
  Future<Result<AttendanceSummary>> getAttendanceSummary({
    required String userId,
    required String groupId,
    required String organizationId,
    required DateTime from,
    required DateTime to,
  });

  /// Fetch paginated attendance history with optional date filters.
  Future<Result<PaginatedResponse<AttendanceModel>>> getAttendanceHistory({
    required String userId,
    required String groupId,
    required String organizationId,
    DateTime? from,
    DateTime? to,
    PaginationParams params,
  });

  /// Fetch all attendance records for an entire group on a specific date.
  Future<Result<List<AttendanceModel>>> getGroupAttendance({
    required String groupId,
    required String organizationId,
    required DateTime date,
  });

  /// Create a new attendance record (first-time mark).
  Future<Result<AttendanceModel>> markAttendance({
    required AttendanceModel record,
  });

  /// Update an existing attendance record (status change, preference update).
  Future<Result<AttendanceModel>> updateAttendance({
    required AttendanceModel record,
  });
}

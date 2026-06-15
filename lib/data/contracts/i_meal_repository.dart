import 'dart:typed_data';

import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Abstract contract for meal configuration and schedule operations.
abstract interface class IMealRepository {
  /// Fetch all active meals configured for [groupId].
  Future<Result<List<MealModel>>> getGroupMeals({
    required String organizationId,
    required String groupId,
  });

  /// Fetch meals active for today (used by student dashboard).
  Future<Result<List<MealModel>>> getTodayMeals({
    required String organizationId,
    required String groupId,
  });

  /// Create a new meal slot. Slot is fully dynamic via [slotKey] + [order].
  Future<Result<MealModel>> createMeal({
    required String organizationId,
    required String groupId,
    required String name,
    required String slotKey,
    required int order,
    required MealAttendanceWindow attendanceWindow,
    String? description,
    List<String> menuItems,
    List<String> availablePreferences,
    List<Uint8List> imageBytes,
  });

  /// Update an existing meal.
  Future<Result<MealModel>> updateMeal({
    required String organizationId,
    required String groupId,
    required String mealId,
    String? name,
    String? description,
    List<String>? menuItems,
    List<String>? availablePreferences,
    MealAttendanceWindow? attendanceWindow,
    bool? isActive,
    List<Uint8List>? imageBytes,
  });

  /// Soft-delete a meal.
  Future<Result<Unit>> deleteMeal({
    required String organizationId,
    required String groupId,
    required String mealId,
  });

  /// Fetch the current week's schedule for [groupId].
  Future<Result<MealScheduleModel>> getCurrentWeekSchedule({
    required String organizationId,
    required String groupId,
  });

  /// Create or update a draft schedule for the current week from [schedule].
  ///
  /// When [schedule.id] is empty a new draft is created (POST /schedules);
  /// otherwise the existing draft is replaced (PATCH /schedules/:id). Returns
  /// the persisted schedule (with a real id) so the caller can publish it.
  Future<Result<MealScheduleModel>> saveSchedule({
    required String organizationId,
    required String groupId,
    required MealScheduleModel schedule,
  });

  /// Publish a draft schedule, making it visible to members.
  Future<Result<MealScheduleModel>> publishSchedule({
    required String organizationId,
    required String groupId,
    required String scheduleId,
  });
}

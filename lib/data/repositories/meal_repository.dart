import 'dart:typed_data';

import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_meal_repository.dart';
import 'package:smart_meal_management/data/mock/mock_meals_data.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// In-memory mock implementation of [IMealRepository].
///
/// All meals are defined via [slotKey] + [order] — no hardcoded MealType enum.
/// Simulates 250 ms latency.
///
/// Uses **static** backing stores so multiple [MealConfigProvider] instances
/// (e.g. MealConfigScreen + MealScheduleScreen) always read the same data.
class MealRepository implements IMealRepository {
  MealRepository() {
    if (_mealsStore.isEmpty) {
      _mealsStore.addAll(MockMealsData.groupMeals());
    }
  }

  // ── Static shared stores ──────────────────────────────────────────────────
  static final List<MealModel> _mealsStore = [];
  static MealScheduleModel? _schedule;
  static int _idCounter = 100;

  static Future<void> _delay() =>
      Future.delayed(const Duration(milliseconds: 250));

  @override
  Future<Result<List<MealModel>>> getGroupMeals({
    required String organizationId,
    required String groupId,
  }) async {
    await _delay();
    final meals = _mealsStore
        .where((m) =>
            m.organizationId == organizationId && m.groupId == groupId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Ok(meals);
  }

  @override
  Future<Result<List<MealModel>>> getTodayMeals({
    required String organizationId,
    required String groupId,
  }) async {
    await _delay();
    final meals = _mealsStore
        .where((m) =>
            m.organizationId == organizationId &&
            m.groupId == groupId &&
            m.isActive)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return Ok(meals);
  }

  @override
  Future<Result<MealModel>> createMeal({
    required String organizationId,
    required String groupId,
    required String name,
    required String slotKey,
    required int order,
    required MealAttendanceWindow attendanceWindow,
    String? description,
    List<String> menuItems = const [],
    List<String> availablePreferences = const [],
    List<Uint8List> imageBytes = const [],
  }) async {
    await _delay();
    try {
      final meal = MealModel(
        id: 'meal_${++_idCounter}',
        groupId: groupId,
        organizationId: organizationId,
        name: name,
        slotKey: slotKey,
        order: order,
        attendanceWindow: attendanceWindow,
        isActive: true,
        description: description,
        menuItems: menuItems,
        imageBytes: imageBytes,
        enabledPreferences: availablePreferences,
        preferencesEnabled: availablePreferences.isNotEmpty,
        createdAt: DateTime.now(),
      );
      _mealsStore.add(meal);
      return Ok(meal);
    } catch (e) {
      return Err(UnexpectedFailure(message: 'Failed to create meal: $e'));
    }
  }

  @override
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
  }) async {
    await _delay();
    final idx = _mealsStore.indexWhere((m) => m.id == mealId);
    if (idx == -1) {
      return const Err(NetworkFailure(message: 'Meal not found.', statusCode: 404));
    }
    final updated = _mealsStore[idx].copyWith(
      name: name,
      description: description,
      menuItems: menuItems,
      attendanceWindow: attendanceWindow,
      isActive: isActive,
      imageBytes: imageBytes,
      enabledPreferences: availablePreferences,
    );
    _mealsStore[idx] = updated;
    return Ok(updated);
  }

  @override
  Future<Result<Unit>> deleteMeal({
    required String organizationId,
    required String groupId,
    required String mealId,
  }) async {
    await _delay();
    final idx = _mealsStore.indexWhere((m) => m.id == mealId);
    if (idx == -1) {
      return const Err(NetworkFailure(message: 'Meal not found.', statusCode: 404));
    }
    _mealsStore.removeAt(idx);
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<MealScheduleModel>> getCurrentWeekSchedule({
    required String organizationId,
    required String groupId,
  }) async {
    await _delay();
    _schedule ??= MockMealsData.weekSchedule(
      groupId: groupId,
      organizationId: organizationId,
    );
    return Ok(_schedule!);
  }

  @override
  Future<Result<MealScheduleModel>> publishSchedule({
    required String organizationId,
    required String groupId,
    required String scheduleId,
  }) async {
    await _delay();
    if (_schedule == null) {
      return const Err(NetworkFailure(message: 'No schedule found.', statusCode: 404));
    }
    _schedule = _schedule!.copyWith(
      isPublished: true,
      publishedAt: DateTime.now(),
    );
    return Ok(_schedule!);
  }
}

import 'dart:typed_data';

import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_meal_repository.dart';
import 'package:smart_meal_management/data/mock/mock_meals_data.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Meal repository with dual-mode dispatch based on [EnvConfig.mockAuthEnabled].
///
/// ## Live mode ([EnvConfig.mockAuthEnabled] == false — B10 default)
/// Calls the NestJS backend via [DioApiService]:
///   - GET    /meals?groupId=&page=&limit=        → list group meals
///   - GET    /meals/today?groupId=               → today's active meals
///   - POST   /meals                              → create meal (CreateMealDto)
///   - PATCH  /meals/:id                          → update meal (UpdateMealDto)
///   - DELETE /meals/:id                          → soft-delete meal
///   - GET    /meals/weekly-schedule?groupId=     → current week schedule (paginated, limit 1)
///   - POST   /schedules/:id/publish              → publish schedule
///
/// All slots are defined via [slotKey] + [order] — no hardcoded MealType enum.
/// Organisation scope is derived server-side from the JWT, never the client.
///
/// ## Mock mode ([EnvConfig.mockAuthEnabled] == true — instant rollback)
/// In-memory store seeded from [MockMealsData]. Static backing stores so
/// multiple [MealConfigProvider] instances share the same data. 250 ms latency.
class MealRepository implements IMealRepository {
  MealRepository() {
    if (_isMock && _mealsStore.isEmpty) {
      _mealsStore.addAll(MockMealsData.groupMeals());
    }
  }

  /// B10: live/mock dispatch — same single switch as the other repositories.
  static bool get _isMock => EnvConfig.current.mockAuthEnabled;

  // -- Static shared stores (mock only) --------------------------------------
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
    if (!_isMock) {
      // B10 LIVE: GET /meals — org scope comes from the JWT, never the client.
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/meals',
        queryParameters: {'groupId': groupId, 'page': '1', 'limit': '100'},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          Ok(PaginatedResponse.fromJson(value, MealModel.fromJson).data),
      };
    }
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
    if (!_isMock) {
      // B10 LIVE: GET /meals/today — backend filters isActive=true server-side.
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/meals/today',
        queryParameters: {'groupId': groupId},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          Ok(PaginatedResponse.fromJson(value, MealModel.fromJson).data),
      };
    }
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
    int? price,
  }) async {
    if (!_isMock) {
      // B10 LIVE: POST /meals — CreateMealDto whitelist only.
      // slotKey is free-form (never an enum) per dynamic rendering contract.
      // imageBytes are NOT uploaded here — R2 multipart upload lands in B11.
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/meals',
        body: {
          'groupId': groupId,
          'slotKey': slotKey,
          'name': name,
          'order': order,
          'attendanceWindow': attendanceWindow.toJson(),
          if (description != null) 'description': description,
          'menuItems': menuItems,
          'preferencesEnabled': availablePreferences.isNotEmpty,
          'enabledPreferences': availablePreferences,
          if (price != null) 'price': price,
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(MealModel.fromJson(value)),
      };
    }
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
        price: price,
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
    int? price,
  }) async {
    if (!_isMock) {
      // B10 LIVE: PATCH /meals/:id — UpdateMealDto partial update.
      // API contract: isActive (DB) is exposed as isEnabled (API).
      final result = await DioApiService.instance.patch<Map<String, dynamic>>(
        '/meals/$mealId',
        body: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (menuItems != null) 'menuItems': menuItems,
          if (attendanceWindow != null)
            'attendanceWindow': attendanceWindow.toJson(),
          if (isActive != null) 'isEnabled': isActive,
          if (availablePreferences != null) ...{
            'enabledPreferences': availablePreferences,
            'preferencesEnabled': availablePreferences.isNotEmpty,
          },
          if (price != null) 'price': price,
        },
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(MealModel.fromJson(value)),
      };
    }
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
      price: price,
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
    if (!_isMock) {
      // B10 LIVE: DELETE /meals/:id — soft-delete server-side.
      final result =
          await DioApiService.instance.delete<dynamic>('/meals/$mealId');
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok() => const Ok(Unit.instance),
      };
    }
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
    if (!_isMock) {
      // B10 LIVE: GET /meals/weekly-schedule — returns a paginated list
      // (limit 1). Extract the first schedule; empty -> blank 7-day schedule.
      final result = await DioApiService.instance.get<Map<String, dynamic>>(
        '/meals/weekly-schedule',
        queryParameters: {'groupId': groupId},
      );
      switch (result) {
        case Err(:final failure):
          return Err(failure);
        case Ok(:final value):
          final page =
              PaginatedResponse.fromJson(value, MealScheduleModel.fromJson);
          if (page.data.isEmpty) {
            return Ok(MealScheduleModel(
              id: '',
              groupId: groupId,
              organizationId: organizationId,
              days: const [],
            ));
          }
          return Ok(page.data.first);
      }
    }
    await _delay();
    _schedule ??= MockMealsData.weekSchedule(
      groupId: groupId,
      organizationId: organizationId,
    );
    return Ok(_schedule!);
  }

  @override
  Future<Result<MealScheduleModel>> saveSchedule({
    required String organizationId,
    required String groupId,
    required MealScheduleModel schedule,
  }) async {
    if (!_isMock) {
      // Build entries[] from the edited days, attaching concrete dates for the
      // current ISO week (Monday = weekStartDate; each day = Monday + index).
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      String fmt(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final entries = <Map<String, dynamic>>[];
      for (final daySchedule in schedule.days) {
        final date = fmt(monday.add(Duration(days: daySchedule.day.index)));
        for (final e in daySchedule.meals) {
          entries.add({
            'mealId': e.mealId,
            'date': date,
            if (e.name.isNotEmpty) 'mealName': e.name,
            if (e.openTime != null && e.closeTime != null)
              'attendanceWindow': {
                'openTime': e.openTime,
                'closeTime': e.closeTime,
              },
            'preferencesEnabled': e.preferencesEnabled,
            'enabledPreferences': e.enabledPreferences,
            // Issue 2: persist per-day menu items so they survive publish and
            // show to students + admin (independent of the master meal menu).
            'menuItems': e.menuItems,
            // Additive: per-day ₹ price override (null = inherit master price).
            if (e.price != null) 'price': e.price,
          });
        }
      }

      if (schedule.id.isEmpty) {
        // CREATE — POST /schedules { groupId, weekStartDate, entries }
        final result = await DioApiService.instance.post<Map<String, dynamic>>(
          '/schedules',
          body: {
            'groupId': groupId,
            'weekStartDate': fmt(monday),
            'entries': entries,
          },
        );
        return switch (result) {
          Err(:final failure) => Err(failure),
          Ok(:final value) => Ok(MealScheduleModel.fromJson(value)),
        };
      }

      // UPDATE — PATCH /schedules/:id { entries, replaceEntries: true }
      final result = await DioApiService.instance.patch<Map<String, dynamic>>(
        '/schedules/${schedule.id}',
        body: {'entries': entries, 'replaceEntries': true},
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(MealScheduleModel.fromJson(value)),
      };
    }
    await _delay();
    _schedule = schedule;
    return Ok(_schedule!);
  }

  @override
  Future<Result<MealScheduleModel>> publishSchedule({
    required String organizationId,
    required String groupId,
    required String scheduleId,
  }) async {
    if (!_isMock) {
      // B10 LIVE: POST /schedules/:id/publish — admin only.
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/schedules/$scheduleId/publish',
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(MealScheduleModel.fromJson(value)),
      };
    }
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

  @override
  Future<Result<MealScheduleModel>> revertSchedule({
    required String organizationId,
    required String groupId,
    required String scheduleId,
  }) async {
    if (!_isMock) {
      // Issue 2 LIVE: POST /schedules/:id/revert — admin only (unpublish).
      final result = await DioApiService.instance.post<Map<String, dynamic>>(
        '/schedules/$scheduleId/revert',
      );
      return switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) => Ok(MealScheduleModel.fromJson(value)),
      };
    }
    await _delay();
    if (_schedule == null) {
      return const Err(NetworkFailure(message: 'No schedule found.', statusCode: 404));
    }
    _schedule = _schedule!.copyWith(isPublished: false);
    return Ok(_schedule!);
  }
}

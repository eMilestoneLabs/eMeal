import 'dart:convert';
import 'dart:typed_data';

import 'package:smart_meal_management/data/contracts/i_meal_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Meal repository — calls the live NestJS backend via [DioApiService].
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
/// Encodes a single compressed meal photo (≤100 KB) as a base64 JPEG data URI
/// carried in the existing `imageUrl` field — works end-to-end with no schema
/// or contract change (server stores the string, clients decode it for display).
String _mealImageDataUri(Uint8List bytes) =>
    'data:image/jpeg;base64,${base64Encode(bytes)}';

class MealRepository implements IMealRepository {
  MealRepository();

  @override
  Future<Result<List<MealModel>>> getGroupMeals({
    required String organizationId,
    required String groupId,
  }) async {
    // GET /meals — org scope comes from the JWT, never the client.
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

  @override
  Future<Result<List<MealModel>>> getTodayMeals({
    required String organizationId,
    required String groupId,
  }) async {
    // GET /meals/today — backend filters isActive=true server-side.
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
    // POST /meals — CreateMealDto whitelist only.
    // slotKey is free-form (never an enum) per dynamic rendering contract.
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/meals',
      body: {
        'groupId': groupId,
        'slotKey': slotKey,
        'name': name,
        'order': order,
        'attendanceWindow': attendanceWindow.toJson(),
        if (description != null) 'description': description,
        // One photo, sent as a base64 data URI in the existing imageUrl field
        // (≤100 KB, compressed). Student/admin decode it for display.
        if (imageBytes.isNotEmpty)
          'imageUrl': _mealImageDataUri(imageBytes.first),
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
    // PATCH /meals/:id — UpdateMealDto partial update.
    // API contract: isActive (DB) is exposed as isEnabled (API).
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/meals/$mealId',
      body: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        // One photo as base64 data URI in imageUrl. Empty list = photo removed
        // → send null to clear it. Null param = field untouched.
        if (imageBytes != null)
          'imageUrl':
              imageBytes.isEmpty ? null : _mealImageDataUri(imageBytes.first),
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

  @override
  Future<Result<Unit>> deleteMeal({
    required String organizationId,
    required String groupId,
    required String mealId,
  }) async {
    // DELETE /meals/:id — soft-delete server-side.
    final result =
        await DioApiService.instance.delete<dynamic>('/meals/$mealId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  @override
  Future<Result<MealScheduleModel>> getCurrentWeekSchedule({
    required String organizationId,
    required String groupId,
  }) async {
    // GET /meals/weekly-schedule — returns a paginated list (limit 1).
    // Extract the first schedule; empty -> blank 7-day schedule.
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

  @override
  Future<Result<MealScheduleModel>> saveSchedule({
    required String organizationId,
    required String groupId,
    required MealScheduleModel schedule,
  }) async {
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
          // Additive: per-day meal description override (null = inherit).
          if (e.description != null) 'description': e.description,
          // Additive: per-day meal photo override (base64 data URI). Absent =
          // inherit master photo; replaceEntries recreates so a removed photo
          // (null) is naturally cleared. One image per entry.
          if (e.imageUrl != null) 'imageUrl': e.imageUrl,
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

  @override
  Future<Result<MealScheduleModel>> publishSchedule({
    required String organizationId,
    required String groupId,
    required String scheduleId,
    MealScheduleModel? schedule,
  }) async {
    // Issue 2: when the local draft is supplied, send its entries so the
    // backend atomically REPLACES + publishes in one transaction. Students
    // keep seeing the previously published week until this commit lands —
    // editing a published week never strands them on the master meal config.
    Map<String, dynamic>? body;
    if (schedule != null) {
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
            'menuItems': e.menuItems,
            if (e.description != null) 'description': e.description,
            if (e.imageUrl != null) 'imageUrl': e.imageUrl,
            if (e.price != null) 'price': e.price,
          });
        }
      }
      body = {'entries': entries, 'replaceEntries': true};
    }
    // POST /schedules/:id/publish — admin only. An entries body triggers atomic
    // replace-and-publish; no body = idempotent flag flip.
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/schedules/$scheduleId/publish',
      body: body,
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(MealScheduleModel.fromJson(value)),
    };
  }

  @override
  Future<Result<MealScheduleModel>> revertSchedule({
    required String organizationId,
    required String groupId,
    required String scheduleId,
  }) async {
    // Issue 2 LIVE: POST /schedules/:id/revert — admin only (unpublish).
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/schedules/$scheduleId/revert',
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(MealScheduleModel.fromJson(value)),
    };
  }
}

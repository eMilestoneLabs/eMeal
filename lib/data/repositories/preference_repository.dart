import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Module 36 (FR-PG-090) data access — preference-group config + analytics.
/// Organisation scope is derived server-side from the JWT.
class PreferenceRepository {
  PreferenceRepository();

  Future<Result<List<PreferenceGroupModel>>> getForMeal(String mealId) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/meals/$mealId/preference-groups',
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok((value['data'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(PreferenceGroupModel.fromJson)
          .toList()),
    };
  }

  /// Live-Test-8 ISSUE-001/002: active + SUSPENDED groups in one read.
  /// `active` = the effective set members see; `suspended` = groups saved
  /// while the meal runs Standalone mode (restored on switch back).
  Future<
      Result<
          ({
            List<PreferenceGroupModel> active,
            List<PreferenceGroupModel> suspended,
          })>> getForMealWithSuspended(String mealId) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/meals/$mealId/preference-groups',
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok((
          active: (value['data'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(PreferenceGroupModel.fromJson)
              .toList(),
          suspended: (value['suspended'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(PreferenceGroupModel.fromJson)
              .toList(),
        )),
    };
  }

  /// Live-Test-8 ISSUE-001/002: non-destructive Standalone↔Groups switch —
  /// suspends (false) or restores (true) ALL of the meal's group bindings.
  Future<Result<Unit>> setMealBindingsActive(
    String mealId, {
    required bool active,
  }) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/meals/$mealId/preference-groups/state',
      body: {'active': active},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  /// Create a meal-scoped group (with inline options) and bind it (FR-PG-080).
  Future<Result<PreferenceGroupModel>> createForMeal({
    required String mealId,
    required Map<String, dynamic> body,
  }) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/meals/$mealId/preference-groups',
      body: body,
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(PreferenceGroupModel.fromJson(value)),
    };
  }

  Future<Result<PreferenceGroupModel>> updateGroup(
    String groupId,
    Map<String, dynamic> body,
  ) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/preference-groups/$groupId',
      body: body,
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(PreferenceGroupModel.fromJson(value)),
    };
  }

  /// Soft-deactivates everywhere (FR-PG-072) — history stays intact.
  Future<Result<Unit>> deactivateGroup(String groupId) async {
    final result = await DioApiService.instance
        .delete<Map<String, dynamic>>('/preference-groups/$groupId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  /// Removes the meal binding only — the group/template survives.
  Future<Result<Unit>> unbindFromMeal(String mealId, String groupId) async {
    final result = await DioApiService.instance.delete<Map<String, dynamic>>(
      '/meals/$mealId/preference-groups/$groupId',
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  Future<Result<PreferenceOptionModel>> addOption(
    String groupId,
    Map<String, dynamic> body,
  ) async {
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/preference-groups/$groupId/options',
      body: body,
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(PreferenceOptionModel.fromJson(value)),
    };
  }

  Future<Result<PreferenceOptionModel>> updateOption(
    String optionId,
    Map<String, dynamic> body,
  ) async {
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/preference-options/$optionId',
      body: body,
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(PreferenceOptionModel.fromJson(value)),
    };
  }

  Future<Result<Unit>> deactivateOption(String optionId) async {
    final result = await DioApiService.instance
        .delete<Map<String, dynamic>>('/preference-options/$optionId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  /// FR-PG-050/051: per-group-per-option counts for the kitchen sheet.
  /// Shape: {date, mealId, data: [{groupId, groupLabel, options: [...]}]}
  Future<Result<Map<String, dynamic>>> getCrossTab({
    required String groupId,
    required String date, // YYYY-MM-DD
    String? mealId,
  }) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/groups/$groupId/preference-crosstab',
      queryParameters: {
        'date': date,
        if (mealId != null) 'mealId': mealId,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(value),
    };
  }
}

import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Dashboard repository — aggregate endpoints that serve a whole screen in a
/// single round-trip (backend composes the same per-endpoint responses).
class DashboardRepository {
  DashboardRepository();

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// One-call admin dashboard aggregate — GET /dashboard/admin/overview.
  ///
  /// Returns the raw JSON body:
  ///   { groups: {data,total,page,limit}, todayMeals: [...],
  ///     mealSummaries: [...], recentActivity: [...], date, generatedAt }
  /// Each element is byte-identical to the corresponding individual endpoint
  /// (/groups, /meals/today, /attendance/meal-summary, /attendance/history),
  /// so callers reuse the existing model parsers. The provider falls back to
  /// the legacy per-endpoint calls when this endpoint is unavailable.
  Future<Result<Map<String, dynamic>>> getAdminOverview({
    required DateTime date,
  }) =>
      DioApiService.instance.get<Map<String, dynamic>>(
        '/dashboard/admin/overview',
        queryParameters: {'date': _dateOnly(date)},
      );
}

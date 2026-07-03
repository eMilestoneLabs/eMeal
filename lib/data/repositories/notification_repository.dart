import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/shared/models/notification_diagnostics_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Push-notification data access beyond token registration (which lives in
/// [PushNotificationService]). Currently: admin delivery diagnostics
/// (FR-NOTX-018 / ISSUE-16). Organisation scope is derived server-side from
/// the JWT — never sent by the client.
class NotificationRepository {
  NotificationRepository();

  /// Admin-only: push channel state, registered device counts, and the most
  /// recent send outcome.
  Future<Result<NotificationDiagnostics>> getDeliveryDiagnostics() async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/notifications/diagnostics',
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => Ok(NotificationDiagnostics.fromJson(value)),
    };
  }
}

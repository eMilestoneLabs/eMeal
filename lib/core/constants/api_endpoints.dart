/// REST API endpoint path constants for the eMeal NestJS backend.
///
/// All values are path segments relative to [EnvConfig.current.apiV1].
/// Never include the base URL here — that lives in [EnvConfig].
///
/// Convention:
/// - Static segment paths use `snake_case` (`/meal_schedules`).
/// - Dynamic segments use `{id}` placeholder strings.
/// - Build full URLs via [ApiEndpoints.buildUrl] or the Dio base URL.
///
/// Usage:
/// ```dart
/// // Simple GET:
/// final response = await dio.get(ApiEndpoints.auth.login);
///
/// // With path param:
/// final url = ApiEndpoints.buildPath(
///   ApiEndpoints.groups.detail,
///   {'groupId': 'grp_123'},
/// );
/// // → '/groups/grp_123'
/// ```
abstract final class ApiEndpoints {
  // ── URL builder helper ─────────────────────────────────────────────────────

  /// Replaces `{key}` placeholders in [template] with [params] values.
  ///
  /// Example:
  /// ```dart
  /// ApiEndpoints.buildPath('/groups/{groupId}/members/{memberId}',
  ///   {'groupId': 'grp_1', 'memberId': 'usr_2'})
  /// // → '/groups/grp_1/members/usr_2'
  /// ```
  static String buildPath(
    String template,
    Map<String, String> params,
  ) {
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  // ── Auth ───────────────────────────────────────────────────────────────────
  static const AuthEndpoints auth = AuthEndpoints._();

  // ── Users ──────────────────────────────────────────────────────────────────
  static const UserEndpoints users = UserEndpoints._();

  // ── Organizations ──────────────────────────────────────────────────────────
  static const OrgEndpoints orgs = OrgEndpoints._();

  // ── Groups ─────────────────────────────────────────────────────────────────
  static const GroupEndpoints groups = GroupEndpoints._();

  // ── Meals ──────────────────────────────────────────────────────────────────
  static const MealEndpoints meals = MealEndpoints._();

  // ── Attendance ─────────────────────────────────────────────────────────────
  static const AttendanceEndpoints attendance = AttendanceEndpoints._();

  // ── Reports / Exports ──────────────────────────────────────────────────────
  static const ReportEndpoints reports = ReportEndpoints._();
}

// ── Endpoint groups ────────────────────────────────────────────────────────────

class AuthEndpoints {
  const AuthEndpoints._();

  /// POST — exchange email+password for access/refresh tokens.
  String get login => '/auth/login';

  /// POST — invalidate the current session server-side.
  String get logout => '/auth/logout';

  /// POST — issue a new access token using the stored refresh token.
  String get refresh => '/auth/refresh';

  /// POST — register a new user account.
  String get register => '/auth/register';

  /// POST — request a password reset email.
  String get forgotPassword => '/auth/forgot-password';

  /// POST — confirm reset token and set a new password.
  String get resetPassword => '/auth/reset-password';

  /// GET — return the authenticated user profile (me endpoint).
  String get me => '/auth/me';
}

class UserEndpoints {
  const UserEndpoints._();

  /// GET — list all users in the organisation (admin only, paginated).
  String get list => '/users';

  /// GET — single user by ID.
  String get detail => '/users/{userId}';

  /// PATCH — update user profile fields.
  String get update => '/users/{userId}';

  /// DELETE — remove a user from the organisation.
  String get delete => '/users/{userId}';

  /// PATCH — toggle vacation mode on/off.
  String get vacationMode => '/users/{userId}/vacation-mode';

  /// PATCH — toggle default attendance on/off.
  String get defaultAttendance => '/users/{userId}/default-attendance';

  /// PATCH — update meal preference selection.
  String get mealPreference => '/users/{userId}/meal-preference';
}

class OrgEndpoints {
  const OrgEndpoints._();

  /// GET — get the authenticated user's organisation details.
  String get detail => '/organisations/{orgId}';

  /// PATCH — update organisation settings.
  String get update => '/organisations/{orgId}';

  /// GET — list all members in the organisation (paginated).
  String get members => '/organisations/{orgId}/members';
}

class GroupEndpoints {
  const GroupEndpoints._();

  /// GET — list all groups for the authenticated org/admin.
  String get list => '/groups';

  /// POST — create a new group.
  String get create => '/groups';

  /// GET — single group by ID.
  String get detail => '/groups/{groupId}';

  /// PATCH — update group settings (name, meal config, etc.).
  String get update => '/groups/{groupId}';

  /// DELETE — archive/delete a group.
  String get delete => '/groups/{groupId}';

  /// GET — list all members of a group (paginated).
  String get members => '/groups/{groupId}/members';

  /// POST — add a member to the group.
  String get addMember => '/groups/{groupId}/members';

  /// DELETE — remove a member from the group.
  String get removeMember => '/groups/{groupId}/members/{userId}';

  /// POST — join a group via QR code token.
  String get joinByQr => '/groups/join';

  /// GET — get/refresh the QR join token for a group (admin only).
  String get qrToken => '/groups/{groupId}/qr-token';

  /// GET — get meal configuration for a group.
  String get mealConfig => '/groups/{groupId}/meal-config';

  /// PUT — replace meal configuration for a group.
  String get updateMealConfig => '/groups/{groupId}/meal-config';
}

class MealEndpoints {
  const MealEndpoints._();

  /// GET — list meals for a group on a specific date.
  /// Query params: `groupId`, `date` (ISO 8601).
  String get list => '/meals';

  /// POST — create a new meal entry (admin only).
  String get create => '/meals';

  /// GET — single meal by ID.
  String get detail => '/meals/{mealId}';

  /// PATCH — update meal details.
  String get update => '/meals/{mealId}';

  /// DELETE — remove a meal entry.
  String get delete => '/meals/{mealId}';

  /// GET — weekly meal schedule for a group.
  /// Query params: `groupId`, `weekStart` (ISO 8601 Monday).
  String get weeklySchedule => '/meals/weekly-schedule';

  /// PUT — publish/replace the weekly schedule (admin only).
  String get updateWeeklySchedule => '/meals/weekly-schedule';

  /// POST — upload a meal image (admin only). Multipart form.
  /// Max 200 KB enforced client-side via [AppConstants.maxMealImageBytes].
  String get uploadImage => '/meals/{mealId}/image';
}

class AttendanceEndpoints {
  const AttendanceEndpoints._();

  /// GET — list attendance records (paginated).
  /// Query params: `groupId`, `userId`, `from`, `to`, `mealType`, `status`.
  String get list => '/attendance';

  /// POST — mark attendance for a meal.
  String get mark => '/attendance';

  /// PATCH — update an existing attendance record (change status/preference).
  String get update => '/attendance/{attendanceId}';

  /// GET — today's attendance summary for a user.
  /// Query params: `userId`, `groupId`.
  String get todaySummary => '/attendance/today';

  /// GET — weekly attendance summary.
  /// Query params: `userId`, `groupId`, `weekStart`.
  String get weeklySummary => '/attendance/weekly-summary';

  /// GET — paginated attendance history for a student.
  String get history => '/attendance/history';
}

class ReportEndpoints {
  const ReportEndpoints._();

  /// GET — download attendance report as PDF.
  /// Query params: `groupId`, `from`, `to`. Returns binary PDF stream.
  String get exportPdf => '/reports/attendance/pdf';

  /// GET — download attendance report as Excel (.xlsx).
  /// Query params: `groupId`, `from`, `to`. Returns binary XLSX stream.
  String get exportExcel => '/reports/attendance/excel';

  /// GET — dashboard analytics summary for admin.
  /// Query params: `groupId`, `period` (today | week | month).
  String get analyticsSummary => '/reports/analytics';

  /// GET — meal-level analytics (preference breakdown, absent rates).
  String get mealAnalytics => '/reports/meals';
}

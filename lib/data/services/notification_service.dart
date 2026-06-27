import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Wrapper around [FlutterLocalNotificationsPlugin] that schedules
/// meal-attendance reminders before each window closes.
///
/// ## Setup
///
/// 1. Call [init] once from `bootstrap.dart`.
/// 2. Register a tap handler via [setNotificationTapHandler] from the root
///    widget so taps navigate the user to the attendance screen.
/// 3. Call [syncReminders] whenever the meal list, vacation mode, or
///    attendance state changes.
///
/// ## Android 13+ (API 33+)
///
/// [init] requests the `POST_NOTIFICATIONS` runtime permission automatically.
/// If denied, notifications are silently skipped — no crash.
///
/// ## Suppression rules
///
/// | Condition              | Effect                           |
/// |------------------------|----------------------------------|
/// | `isVacationMode=true`  | All reminders cancelled          |
/// | Meal in `markedMealIds`| Reminders for that meal skipped  |
/// | Window already passed  | Reminder not scheduled           |
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // ── Tap handler ────────────────────────────────────────────────────────────

  /// Called when the user taps a notification.
  ///
  /// Register this from your root widget (e.g. in [initState] or a
  /// [WidgetsBindingObserver]):
  /// ```dart
  /// NotificationService.setNotificationTapHandler((payload) {
  ///   if (payload == 'attendance') {
  ///     context.go(AppRoutes.attendance);
  ///   }
  /// });
  /// ```
  static void Function(String? payload)? _onNotificationTap;

  /// Registers the global tap handler.  Safe to call multiple times
  /// (e.g. on every hot-restart); the last registration wins.
  static void setNotificationTapHandler(
      void Function(String? payload) handler) {
    _onNotificationTap = handler;
  }

  /// Invokes the registered tap handler with [payload].
  ///
  /// Used by [PushNotificationService] so that a tap on an FCM-drawn
  /// notification (background / terminated) deep-links through the SAME router
  /// wiring as a local-notification tap. No-op if no handler is registered.
  static void handleRoutePayload(String? payload) {
    if (payload != null) _onNotificationTap?.call(payload);
  }

  // ── Init ───────────────────────────────────────────────────────────────────

  /// Initialises the notification plugin, wires the tap callback, and
  /// requests the Android 13+ POST_NOTIFICATIONS permission.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;

    // Initialise timezone database — required before any zonedSchedule call.
    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      // Fired when the user taps a notification while the app is in
      // foreground, background, or terminated.
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _onNotificationTap?.call(response.payload);
      },
      // Also handle background isolate taps (app was terminated).
      onDidReceiveBackgroundNotificationResponse: _backgroundNotificationHandler,
    );

    // Request Android 13+ POST_NOTIFICATIONS permission.
    // On older SDK versions this is a no-op.
    await _requestAndroidPermission();

    _initialized = true;
  }

  /// Requests the runtime notification permission on Android 13+ (API 33+).
  Future<void> _requestAndroidPermission() async {
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.requestNotificationsPermission();
    }
  }

  // ── Reminders ──────────────────────────────────────────────────────────────

  /// Schedules (or re-schedules) attendance reminders for [meals].
  ///
  /// ### Three reminders per meal (PRD spec)
  ///
  /// | Offset | Title                                  |
  /// |--------|----------------------------------------|
  /// | −60 min| "{meal} window closes in 1 hour"       |
  /// | −30 min| "{meal} window closes soon"            |
  /// | −10 min| "Last chance — {meal}"                 |
  ///
  /// ### Suppression rules
  ///
  /// - If [isVacationMode] is `true` all pending reminders are cancelled and
  ///   no new ones are created.
  /// - If a meal's ID appears in [markedMealIds] its reminders are skipped
  ///   (the student already marked attendance).
  /// - Reminder times that have already passed are silently skipped.
  ///
  /// Cancels ids 1000–1149 (reserved for meal reminders; 50 meals × 3 slots)
  /// before scheduling fresh ones, so stale entries don't linger after admin
  /// schedule changes.
  Future<void> syncReminders(
    List<MealModel> meals, {
    bool isVacationMode = false,
    Set<String> markedMealIds = const {},
  }) async {
    if (!_initialized) return;

    // Cancel all pending notifications in a single call.
    // Replaces the previous O(150) sequential-await loop (1000–1149 range).
    await _plugin.cancelAll();

    // No reminders during vacation mode.
    if (isVacationMode) return;

    if (meals.isEmpty) return;

    final now = DateTime.now();
    int notifId = 1000;

    for (final meal in meals) {
      if (!meal.isActive) continue;

      // Skip meals already marked — no reminder needed.
      if (markedMealIds.contains(meal.id)) continue;

      final windowParts = meal.attendanceWindow.closeTime.split(':');
      if (windowParts.length < 2) continue;

      final closeHour = int.tryParse(windowParts[0]) ?? 0;
      final closeMin = int.tryParse(windowParts[1]) ?? 0;

      final closeTime = DateTime(
        now.year,
        now.month,
        now.day,
        closeHour,
        closeMin,
      );

      // 1. Schedule 1-hour reminder (PRD: "attendance ends in 1 hour")
      final remind60 = closeTime.subtract(const Duration(minutes: 60));
      if (remind60.isAfter(now)) {
        await _scheduleReminder(
          id: notifId++,
          title: '${meal.name} window closes in 1 hour',
          body:
              'Remember to mark your attendance before ${TimeFormat.hm12(meal.attendanceWindow.closeTime)}.',
          scheduledAt: remind60,
          payload: RouteNames.studentAttendance,
        );
      } else {
        notifId++; // Keep slot reserved even when reminder is already past.
      }

      // 2. Schedule 30-minute reminder (PRD: "attendance ends in 30 minutes")
      final remind30 = closeTime.subtract(const Duration(minutes: 30));
      if (remind30.isAfter(now)) {
        await _scheduleReminder(
          id: notifId++,
          title: '${meal.name} window closes soon',
          body:
              'Mark your attendance before ${TimeFormat.hm12(meal.attendanceWindow.closeTime)}.',
          scheduledAt: remind30,
          payload: RouteNames.studentAttendance,
        );
      } else {
        notifId++;
      }

      // 3. Schedule 10-minute last-chance reminder
      final remind10 = closeTime.subtract(const Duration(minutes: 10));
      if (remind10.isAfter(now)) {
        await _scheduleReminder(
          id: notifId++,
          title: 'Last chance — ${meal.name}',
          body:
              'Attendance window closes at ${TimeFormat.hm12(meal.attendanceWindow.closeTime)}!',
          scheduledAt: remind10,
          payload: RouteNames.studentAttendance,
        );
      } else {
        notifId++;
      }
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<void> _scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? payload,
  }) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'meal_reminders',
          'Meal Reminders',
          channelDescription:
              'Reminders before meal attendance windows close.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  // ── Public helpers ─────────────────────────────────────────────────────────

  /// Cancels every scheduled notification (including non-meal ones).
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// Shows an immediate (non-scheduled) notification — useful for feedback,
  /// and for displaying FCM **foreground** pushes (Android does not draw a
  /// system notification while the app is open, so we draw one ourselves).
  ///
  /// [payload] is forwarded to the tap handler registered via
  /// [setNotificationTapHandler] so a tap can deep-link (e.g. a route path).
  /// [id] lets callers avoid clobbering each other (each push gets a unique id).
  Future<void> showInstant({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'meal_instant',
          'Meal Notifications',
          channelDescription: 'Instant meal notifications.',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }
}

// ── Background tap handler (top-level, required by flutter_local_notifications) ─

/// Top-level function required by [FlutterLocalNotificationsPlugin] for
/// background notification responses.
///
/// Must be a top-level function (not a class method or lambda) so that the
/// background isolate can find and call it.
@pragma('vm:entry-point')
void _backgroundNotificationHandler(NotificationResponse response) {
  // In background/terminated state we can only perform lightweight work.
  // The foreground handler set via [NotificationService.setNotificationTapHandler]
  // will handle navigation once the app is foregrounded by the tap.
}

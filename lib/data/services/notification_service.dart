import 'package:flutter/services.dart' show PlatformException;
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
  /// Live-Test-11 P1 (single-notification rule): set by
  /// [PushNotificationService] once the device's FCM token is registered with
  /// the backend. The backend then owns the 30-min and 10-min window-close
  /// reminders (FCM push), so the matching LOCAL reminders are suppressed —
  /// the same reminder must never arrive twice. The 60-min local reminder has
  /// no push counterpart and always stays scheduled (fail-safe early warning).
  static bool pushRemindersActive = false;

  Future<void> syncReminders(
    List<MealModel> meals, {
    bool isVacationMode = false,
    Set<String> markedMealIds = const {},
  }) async {
    if (!_initialized) return;

    // Cancel only the MEAL reminder slots (ids 1000–1149) — never wipes
    // notifications owned by other features (notepad reminders live in their
    // own id range).
    await _cancelMealReminderRange();

    // No reminders during vacation mode.
    if (isVacationMode) return;

    if (meals.isEmpty) return;

    final now = DateTime.now();
    int notifId = _mealReminderBaseId;

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
      // P1 single-notification rule: skipped when the backend FCM reminder
      // (same 30-min offset) will reach this device — see [pushRemindersActive].
      final remind30 = closeTime.subtract(const Duration(minutes: 30));
      if (pushRemindersActive) {
        notifId += 2; // keep the 30-min and 10-min slots reserved
        continue;
      }
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

  /// Live-Test-11 ISSUE-021: exact-alarm fail-safe. Android 14+ denies
  /// SCHEDULE_EXACT_ALARM by default for sideloaded/new installs — an exact
  /// zonedSchedule then throws `exact_alarms_not_permitted` and the reminder
  /// silently never fires. Retrying with an INEXACT mode still delivers the
  /// notification (the OS may shift it by a few minutes) — reliably late
  /// beats reliably never.
  Future<void> _zonedScheduleWithFallback(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details, {
    String? payload,
  }) async {
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } on PlatformException {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }

  /// ISSUE-021 permission flow: when Android denies exact alarms (14+ default),
  /// ask once via the system "Alarms & reminders" screen. Safe no-op on iOS,
  /// on already-granted devices, and on plugin versions without the API.
  Future<void> ensureExactAlarmPermission() async {
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin == null) return;
      final canExact =
          await androidPlugin.canScheduleExactNotifications() ?? true;
      if (!canExact) {
        await androidPlugin.requestExactAlarmsPermission();
      }
    } catch (_) {
      // Fail soft — the inexact fallback still delivers reminders.
    }
  }

  Future<void> _scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? payload,
  }) async {
    await _zonedScheduleWithFallback(
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
      payload: payload,
    );
  }

  // ── Notification id ranges (one range per owning feature) ──────────────────

  /// Meal reminders: 1000–1149 (50 meals × 3 slots) — see [syncReminders].
  static const int _mealReminderBaseId = 1000;
  static const int _mealReminderEndId = 1150;

  /// Personal-notepad reminders: 200000–299999. Ids are derived
  /// deterministically from the note id so re-scheduling the same note
  /// replaces its previous alarm instead of stacking a duplicate.
  static const int _noteReminderBaseId = 200000;
  static const int _noteReminderSpan = 100000;

  /// Cancels every pending notification in the meal-reminder id range.
  /// Listing pending requests first keeps this O(actually-scheduled) instead
  /// of O(150); the range loop is only the fallback.
  Future<void> _cancelMealReminderRange() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= _mealReminderBaseId && p.id < _mealReminderEndId) {
          await _plugin.cancel(p.id);
        }
      }
    } catch (_) {
      for (var id = _mealReminderBaseId; id < _mealReminderEndId; id++) {
        await _plugin.cancel(id);
      }
    }
  }

  /// Cancels only meal reminders (settings toggle / vacation mode) — leaves
  /// notifications owned by other features (personal notepad) untouched.
  Future<void> cancelMealReminders() async {
    if (!_initialized) return;
    await _cancelMealReminderRange();
  }

  static int _noteNotificationId(String noteId) {
    // FNV-1a — stable across launches (String.hashCode is not guaranteed to be).
    var h = 0x811C9DC5;
    for (final c in noteId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7FFFFFFF;
    }
    return _noteReminderBaseId + (h % _noteReminderSpan);
  }

  // ── Notepad reminders ───────────────────────────────────────────────────────

  /// Schedules (or replaces) the device-local reminder for a personal note.
  /// No-op when the service is not initialised or [when] is already past.
  /// The note's content stays on-device — only the title is shown.
  Future<void> scheduleNoteReminder({
    required String noteId,
    required String title,
    required DateTime when,
  }) async {
    if (!_initialized) return;
    if (!when.isAfter(DateTime.now())) return;
    try {
      // ISSUE-021: exact first, inexact fallback — a denied exact-alarm
      // permission (Android 14+ default) must delay a reminder by minutes,
      // never swallow it entirely (the old single-mode call did).
      await _zonedScheduleWithFallback(
        _noteNotificationId(noteId),
        title.trim().isEmpty ? 'Note reminder' : title.trim(),
        'Tap to open your note.',
        tz.TZDateTime.from(when, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'note_reminders',
            'Notepad Reminders',
            channelDescription: 'Reminders you set on personal notes.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: RouteNames.notepad,
      );
    } catch (_) {
      // Fail soft — a reminder that cannot be scheduled must never crash the
      // notepad (even the inexact mode can throw on exotic OEM builds).
    }
  }

  /// Cancels the reminder for a personal note (no-op when none is pending).
  Future<void> cancelNoteReminder(String noteId) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_noteNotificationId(noteId));
    } catch (_) {
      // Fail soft.
    }
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
    String? tag,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        // PRIORITY-1 (duplicate fix): the Android `tag` + a stable `id` make a
        // repeat of the SAME logical push REPLACE the existing notification
        // instead of stacking a second copy.
        android: AndroidNotificationDetails(
          'meal_instant',
          'Meal Notifications',
          channelDescription: 'Instant meal notifications.',
          importance: Importance.defaultImportance,
          tag: tag,
        ),
        iOS: const DarwinNotificationDetails(),
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

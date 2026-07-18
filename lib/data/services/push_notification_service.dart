import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/features/auth/models/auth_state.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/app/router/route_names.dart';

/// PushNotificationService — Firebase Cloud Messaging (FCM) integration.
///
/// ## Design: ADDITIVE + graceful degradation (mirrors the backend)
///
/// This service is **opt-in at the native layer**. Until the project has been
/// wired to Firebase (`flutterfire configure`, which adds
/// `google-services.json` / `GoogleService-Info.plist`), [Firebase.initializeApp]
/// throws — we **catch it and disable push**. The app then behaves EXACTLY as it
/// did before this feature existed: local attendance reminders still work, no
/// crash, no broken build. This is the same env-gated philosophy the backend
/// uses (no `FIREBASE_*` env → push is log-only).
///
/// ## What it does once Firebase IS configured
///
/// - Requests notification permission (iOS prompt; Android 13+ runtime).
/// - Reads the device FCM token and registers it with the backend
///   (`POST /auth/fcm-token`) whenever the user becomes authenticated, and again
///   on token rotation.
/// - **Foreground** messages: Android draws nothing while the app is open, so we
///   render one via [NotificationService.showInstant] (with a deep-link payload).
/// - **Background / terminated** taps: routes through the same handler the local
///   notifications use, via [NotificationService.handleRoutePayload].
///
/// ## One-time activation (app owner, NOT a code change)
///
/// ```bash
/// dart pub global activate flutterfire_cli
/// flutterfire configure --project=emeal-144d4   # writes native config + options
/// ```
/// iOS additionally needs the APNs key uploaded in the Firebase console and the
/// Push Notifications + Background Modes capabilities enabled in Xcode.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  bool _enabled = false;
  bool _initialized = false;

  /// Last token successfully sent to the backend — avoids duplicate POSTs.
  String? _lastRegisteredToken;

  /// True only when Firebase initialised AND messaging is usable.
  bool get isEnabled => _enabled;

  // ── Init ────────────────────────────────────────────────────────────────────

  /// Initialises Firebase + FCM. Safe to call once from `bootstrap.dart`.
  ///
  /// NEVER throws: any failure (most commonly "Firebase not configured yet")
  /// disables push and leaves the rest of the app untouched.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // No explicit options → uses native google-services.json / plist.
      // Throws if the native Firebase config is absent (feature not activated).
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint(
        '[Push] Firebase not configured — push disabled (app unaffected). $e',
      );
      _enabled = false;
      return;
    }

    try {
      // Background / terminated message handler (top-level, see bottom of file).
      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // iOS permission prompt; Android 13+ runtime permission.
      await messaging.requestPermission();

      // Show heads-up notifications on iOS while the app is foregrounded.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Foreground: draw our own notification (Android shows nothing otherwise).
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Tapped while app was backgrounded.
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);

      // App launched from terminated by tapping a push.
      final initial = await messaging.getInitialMessage();
      if (initial != null) _onMessageOpenedApp(initial);

      // Re-register if Firebase rotates the token.
      messaging.onTokenRefresh.listen((token) {
        _lastRegisteredToken = null; // force re-send of the new token
        _registerToken(token);
      });

      _enabled = true;
      debugPrint('[Push] FCM enabled.');
    } catch (e) {
      debugPrint('[Push] FCM setup failed — push disabled. $e');
      _enabled = false;
    }
  }

  // ── Auth lifecycle ──────────────────────────────────────────────────────────

  /// Hooked to [AuthProvider] changes from `bootstrap.dart`.
  ///
  /// On authentication, (re)registers the device token with the backend. On
  /// logout, clears the cached token so the next login re-registers.
  void onAuthChanged(AuthState state) {
    if (!_enabled) return;
    if (state is AuthAuthenticated) {
      registerTokenWithBackend();
    } else if (state is AuthUnauthenticated) {
      _lastRegisteredToken = null;
      // Local reminders resume ownership until the next successful registration.
      NotificationService.pushRemindersActive = false;
    }
  }

  /// Reads the current FCM token and registers it with the backend.
  /// Best-effort: never throws.
  Future<void> registerTokenWithBackend() async {
    if (!_enabled) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      debugPrint('[Push] getToken failed: $e');
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  Future<void> _registerToken(String token) async {
    if (token == _lastRegisteredToken) return; // already sent
    // DioApiService auto-injects the Bearer access token; requiresAuth=true.
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/auth/fcm-token',
      body: {'token': token},
    );
    switch (result) {
      case Ok():
        _lastRegisteredToken = token;
        // P1 single-notification rule: the backend now owns the 30/10-min
        // window-close reminders for this device — suppress the local copies.
        NotificationService.pushRemindersActive = true;
        debugPrint('[Push] FCM token registered with backend.');
      case Err(:final failure):
        debugPrint('[Push] FCM token registration failed: ${failure.message}');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    if (title == null && body == null) return;
    // PRIORITY-1 (duplicate fix): render with a STABLE id + tag derived from the
    // backend collapse key (`dedupeId`). A re-delivery of the same logical push
    // then REPLACES the visible notification instead of showing a second copy.
    final dedupe = (message.data['dedupeId'] ??
            message.data['type'] ??
            message.messageId ??
            '${title ?? ''}|${body ?? ''}')
        .toString();
    NotificationService.instance.showInstant(
      title: title ?? 'MealAttend',
      body: body ?? '',
      payload: _routeOf(message),
      id: _stableNotificationId(dedupe),
      tag: dedupe,
    );
  }

  /// Deterministic 31-bit notification id from a string (FNV-1a) so the same
  /// [dedupe] key always maps to the same notification slot.
  int _stableNotificationId(String s) {
    var h = 0x811C9DC5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7FFFFFFF;
    }
    return h;
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    NotificationService.handleRoutePayload(_routeOf(message));
  }

  /// Deep-link route carried in the push `data` payload, if any.
  ///
  /// Backend contract (notification-payload.service.ts): every payload carries
  /// `data: { route: <frontend route>, type: <kind>, ... }`. Two backend routes
  /// differ from the frozen frontend router paths, so we map them to the
  /// canonical [RouteNames] constants (grounded in BOTH contracts, not guesses).
  /// Every other backend route already matches a frontend path and passes
  /// through unchanged.
  String? _routeOf(RemoteMessage message) {
    final raw = message.data['route'];
    if (raw is! String || raw.isEmpty) return null;
    switch (raw) {
      // schedule_published -> frontend Weekly Menu screen ('/student/menu').
      case '/student/weekly-menu':
        return RouteNames.studentWeeklyMenu;
      // event_joined (event GUEST) -> frontend event-guest dashboard ('/event-guest').
      case '/event/dashboard':
        return RouteNames.eventGuestDashboard;
      default:
        return raw;
    }
  }
}

// ── Background message handler (top-level, required by firebase_messaging) ─────

/// Handles messages delivered while the app is in the background or terminated.
///
/// Must be a top-level / static function annotated with `@pragma('vm:entry-point')`
/// because it runs in a separate background isolate. The system tray notification
/// for "notification" messages is drawn by the OS automatically — we only need to
/// ensure Firebase is initialised in this isolate.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // If Firebase isn't configured this isolate simply does nothing.
  }
}

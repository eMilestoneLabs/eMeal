import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/app/app.dart';
import 'package:smart_meal_management/app/router/app_router.dart';
import 'package:smart_meal_management/app/router/notification_route_resolver.dart';
import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/data/services/push_notification_service.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/providers/theme_provider.dart';

/// Application bootstrap — runs before [runApp].
///
/// Startup contract (Issue 2 — "white screen after long use / reinstall-only"):
/// only synchronous wiring happens before [runApp], so the splash frame paints
/// within milliseconds even on a hung, offline, or slow network. ALL I/O
/// (notification + FCM init, session restore, cache prune) runs AFTER the first
/// frame and is individually guarded + time-bounded, so no awaited dependency
/// can ever block the app from reaching a renderable state. The router shows
/// the splash while auth is [AuthUnknown] and redirects once it resolves.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // ── Synchronous wiring only — NO I/O before the first frame ────────────────
  final authProvider = AuthProvider(); // starts in AuthUnknown
  final themeProvider = ThemeProvider();
  final router = buildRouter(authProvider);

  // Wire the notification tap handler now that the router exists (capture only;
  // no I/O). Routing a tapped notification still works once init completes.
  // Payload routes are resolved against the registered router paths (legacy
  // role-agnostic routes like '/billing' map per role) so a tap never 404s.
  NotificationService.setNotificationTapHandler((routePath) {
    if (routePath != null) {
      router.go(resolveNotificationRoute(routePath, authProvider));
    }
  });

  // ── First frame NOW — splash renders instantly regardless of network ───────
  runApp(
    MealAttendApp(
      authProvider: authProvider,
      themeProvider: themeProvider,
      router: router,
    ),
  );

  // ── Connection pre-warm (fire-and-forget) ──────────────────────────────────
  // Open the DNS + TCP + TLS + ALPN(h2) connection to the API while the splash
  // intro plays, so the FIRST real request (dashboard load) reuses a warm
  // connection instead of paying the full cold handshake — the single biggest
  // fixed cost on a high-RTT link. GET /health is @Public (no auth, no side
  // effects) and the Result API never throws; a failure changes nothing.
  unawaited(
    DioApiService.instance.get<dynamic>('/health', requiresAuth: false),
  );

  // ── Post-frame: resolve the session so the router can redirect a restored ──
  // user to their dashboard. Now a PURE LOCAL READ (instant boot) — the server
  // session check runs in the background inside AuthProvider. Never throws.
  await authProvider.initialize();

  // Best-effort background services (notifications, FCM token, cache prune).
  // Fire-and-forget + fully guarded so a failure can never affect the running
  // app. Passes the resolved auth state so FCM registers the current session.
  unawaited(_initBackgroundServices(authProvider));
}

/// Initialises non-critical subsystems after the first frame. Every step is
/// wrapped + time-bounded so a single hang/throw is isolated.
Future<void> _initBackgroundServices(AuthProvider authProvider) async {
  final timeout = EnvConfig.current.connectTimeout;

  try {
    await NotificationService.instance.init().timeout(timeout);
  } catch (_) {/* notifications are non-critical */}

  try {
    await PushNotificationService.instance.init().timeout(timeout);
  } catch (_) {/* push self-disables when Firebase isn't configured */}

  // Register the device's FCM token for the (possibly restored) session, then
  // on every auth change. Guarded so a Firebase/token failure stays silent.
  try {
    PushNotificationService.instance.onAuthChanged(authProvider.state);
    authProvider.addListener(
      () => PushNotificationService.instance.onAuthChanged(authProvider.state),
    );
  } catch (_) {/* token registration is best-effort */}

  // Self-heal: drop expired + corrupt SWR entries and bound date-keyed growth.
  try {
    await ResponseCacheService.instance.prune(EnvConfig.current.cacheMaxAge);
  } catch (_) {/* best-effort */}
}

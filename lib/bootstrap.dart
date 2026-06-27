import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_meal_management/app/app.dart';
import 'package:smart_meal_management/app/router/app_router.dart';
import 'package:smart_meal_management/data/services/notification_service.dart';
import 'package:smart_meal_management/data/services/push_notification_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/providers/theme_provider.dart';

/// Application bootstrap — runs before [runApp].
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

  // Initialise notification service
  await NotificationService.instance.init();

  // Initialise push notifications (FCM). Self-disables if Firebase isn't
  // configured yet — never blocks startup, never throws.
  await PushNotificationService.instance.init();

  // Restore or create a fresh auth session
  final authProvider = AuthProvider();
  await authProvider.initialize();

  // Register the device's FCM token with the backend whenever the user is
  // authenticated — once for a restored session, then on every auth change.
  PushNotificationService.instance.onAuthChanged(authProvider.state);
  authProvider.addListener(
    () => PushNotificationService.instance.onAuthChanged(authProvider.state),
  );

  final themeProvider = ThemeProvider();
  final router = buildRouter(authProvider);

  // Wire notification tap handler now that the router exists.
  //
  // This must happen after buildRouter so the router ref is captured.
  NotificationService.setNotificationTapHandler((routePath) {
    if (routePath != null) router.go(routePath);
  });

  runApp(
    MealAttendApp(
      authProvider: authProvider,
      themeProvider: themeProvider,
      router: router,
    ),
  );
}

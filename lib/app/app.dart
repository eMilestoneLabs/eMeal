import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/core/theme/app_theme.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/providers/theme_provider.dart';

/// Root widget of the MealAttend application.
///
/// Accepts an [authProvider] and [themeProvider] from [bootstrap.dart] so they
/// can be injected during tests without touching the widget tree.
class MealAttendApp extends StatelessWidget {
  const MealAttendApp({
    super.key,
    required this.authProvider,
    required this.themeProvider,
    required this.router,
  });

  final AuthProvider authProvider;
  final ThemeProvider themeProvider;
  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    // ThemeProviderScope makes ThemeProvider.of(context) callable from any
    // descendant screen — e.g. settings screens that toggle dark/light mode.
    // ListenableBuilder above it rebuilds MaterialApp.router when theme changes.
    return ThemeProviderScope(
      notifier: themeProvider,
      child: AuthProviderScope(
        provider: authProvider,
        child: ListenableBuilder(
          listenable: themeProvider,
          builder: (context, _) {
            // Reactively sync status-bar icon brightness with the active theme.
            // Bootstrap sets an initial value, but ThemeProvider changes (e.g.
            // user toggling dark mode in Settings) must update the overlay style
            // so icons remain visible in both light and dark modes.
            final isDark = themeProvider.themeMode == ThemeMode.dark ||
                (themeProvider.themeMode == ThemeMode.system &&
                    WidgetsBinding
                            .instance.platformDispatcher.platformBrightness ==
                        Brightness.dark);

            SystemChrome.setSystemUIOverlayStyle(
              SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              ),
            );

            return MaterialApp.router(
              title: 'MealAttend',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeProvider.themeMode,
              routerConfig: router,
            );
          },
        ),
      ),
    );
  }
}

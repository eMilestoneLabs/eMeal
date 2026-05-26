import 'package:flutter/material.dart';

/// App-wide theme mode provider.
///
/// Wraps [ThemeMode] state in a [ChangeNotifier] and exposes it via
/// [ThemeProviderScope] (an [InheritedNotifier]).
///
/// ### Usage
/// Wrap a subtree (typically the root app widget) with [ThemeProviderScope]:
/// ```dart
/// ThemeProviderScope(
///   notifier: themeProvider,
///   child: MaterialApp.router(...),
/// )
/// ```
/// Then read from any descendant widget:
/// ```dart
/// final provider = ThemeProvider.of(context);
/// provider.setThemeMode(ThemeMode.dark);
/// ```
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isLight => _themeMode == ThemeMode.light;
  bool get isSystem => _themeMode == ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }

  void toggleTheme() {
    setThemeMode(_themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  /// Returns the [ThemeProvider] from the nearest [ThemeProviderScope] ancestor.
  ///
  /// Throws an assertion error in debug mode if no scope is found — this means
  /// [ThemeProviderScope] was not placed above this widget in the tree.
  static ThemeProvider of(BuildContext context) {
    final widget =
        context.findAncestorWidgetOfExactType<ThemeProviderScope>();
    assert(
      widget != null,
      'ThemeProvider.of() called without a ThemeProviderScope ancestor.\n'
      'Ensure ThemeProviderScope wraps your app in bootstrap.dart or app.dart.',
    );
    return widget!.notifier!;
  }
}

/// Provides [ThemeProvider] to the widget subtree via [InheritedNotifier].
///
/// Place this above [MaterialApp] so all screens can access the theme provider.
/// [ThemeProviderScope] is intentionally PUBLIC — unlike the old private
/// [_ThemeProviderScope] it replaced — so it can be used in settings screens,
/// tests, and any widget that needs to toggle or read the current theme mode.
class ThemeProviderScope extends InheritedNotifier<ThemeProvider> {
  const ThemeProviderScope({
    super.key,
    required super.notifier,
    required super.child,
  });

  @override
  bool updateShouldNotify(ThemeProviderScope oldWidget) =>
      notifier?.themeMode != oldWidget.notifier?.themeMode;
}

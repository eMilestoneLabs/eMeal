// AppLogger – structured debug / error / info logging utility.

import 'package:flutter/foundation.dart';

/// Structured logger for the MealAttend app.
///
/// In debug mode, messages are printed with level prefix.
/// In release builds, debug/info logs are suppressed.
abstract final class AppLogger {
  static void debug(String message, [Object? data]) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message${data != null ? ' | $data' : ''}');
    }
  }

  static void info(String message, [Object? data]) {
    if (kDebugMode) {
      debugPrint('[INFO]  $message${data != null ? ' | $data' : ''}');
    }
  }

  static void warning(String message, [Object? data]) {
    debugPrint('[WARN]  $message${data != null ? ' | $data' : ''}');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[ERROR] $message');
    if (error != null) debugPrint('        Error: $error');
    if (stackTrace != null && kDebugMode) {
      debugPrint('        Stack: $stackTrace');
    }
  }
}

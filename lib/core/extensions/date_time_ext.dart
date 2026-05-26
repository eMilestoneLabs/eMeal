import 'package:flutter/material.dart';

/// [DateTime] extension helpers used throughout the MealAttend app.
extension DateTimeExt on DateTime {
  /// True when this date is the same calendar day as [other].
  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  /// True when this is today.
  bool get isToday => isSameDay(DateTime.now());

  /// True when this is yesterday.
  bool get isYesterday =>
      isSameDay(DateTime.now().subtract(const Duration(days: 1)));

  /// Returns the date portion (zeroed time fields).
  DateTime get dateOnly => DateTime(year, month, day);

  /// Formats as "DD Mon YYYY" (e.g. "12 Jan 2025").
  String get formatted {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '$day ${months[month - 1]} $year';
  }

  /// Formats as "HH:mm" (e.g. "09:30").
  String get timeFormatted =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Converts to a [TimeOfDay].
  TimeOfDay get timeOfDay => TimeOfDay(hour: hour, minute: minute);

  /// Returns the [DayOfWeek]-equivalent index (0 = Monday).
  int get weekdayIndex => (weekday - 1) % 7;
}

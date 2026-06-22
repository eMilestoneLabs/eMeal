import 'package:flutter/material.dart';

/// Centralised 12-hour (AM/PM) time formatting for the whole app.
///
/// CONTRACT NOTE (additive / display-only): meal attendance windows are stored
/// and transmitted to the backend as strict 24-hour `"HH:mm"` strings (the
/// backend regex is `^([01]\d|2[0-3]):[0-5]\d$`). This helper changes ONLY how
/// those values are *rendered* to humans — it never alters stored or sent data.
///
/// Every admin and student screen must display meal/attendance times through
/// these helpers so the entire app shows one consistent AM/PM format
/// (e.g. `7:00 AM`, `1:00 PM`) regardless of the device's 24-hour locale
/// setting.
class TimeFormat {
  const TimeFormat._();

  /// Converts a stored `"HH:mm"` 24-hour string to a 12-hour AM/PM label.
  ///
  /// Examples: `"07:00" -> "7:00 AM"`, `"13:00" -> "1:00 PM"`,
  /// `"00:00" -> "12:00 AM"`, `"23:59" -> "11:59 PM"`.
  ///
  /// If [hhmm] cannot be parsed it is returned unchanged so nothing ever
  /// renders as an error.
  static String hm12(String? hhmm) {
    if (hhmm == null) return '';
    final s = hhmm.trim();
    if (s.isEmpty) return '';
    final parts = s.split(':');
    if (parts.length < 2) return s;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return s;
    }
    return _format(h, m);
  }

  /// Converts a [TimeOfDay] to a 12-hour AM/PM label (locale-independent).
  static String tod12(TimeOfDay t) => _format(t.hour, t.minute);

  /// Formats an open–close window as a single 12-hour AM/PM range using an
  /// en-dash separator, e.g. `"7:00 AM – 11:00 AM"`.
  static String window12(String? open, String? close) =>
      '${hm12(open)} – ${hm12(close)}';

  static String _format(int hour24, int minute) {
    final period = hour24 >= 12 ? 'PM' : 'AM';
    var h = hour24 % 12;
    if (h == 0) h = 12;
    final mm = minute.toString().padLeft(2, '0');
    return '$h:$mm $period';
  }
}

/// `showTimePicker` builder that forces a 12-hour AM/PM dial regardless of the
/// device locale's 24-hour setting.
Widget forceAmPmTimePicker(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
      child: child!,
    );

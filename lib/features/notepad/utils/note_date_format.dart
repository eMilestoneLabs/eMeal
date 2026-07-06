import 'package:intl/intl.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';

/// Day-wise section buckets for the notepad list.
enum NoteDaySection { today, yesterday, thisWeek, older }

extension NoteDaySectionLabel on NoteDaySection {
  String get label => switch (this) {
    NoteDaySection.today => 'Today',
    NoteDaySection.yesterday => 'Yesterday',
    NoteDaySection.thisWeek => 'This Week',
    NoteDaySection.older => 'Older',
  };
}

/// Pure date helpers for the notepad (no state, easily unit-testable).
abstract final class NoteDateFormat {
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Buckets [when] relative to [now] (defaults to `DateTime.now()`).
  static NoteDaySection sectionFor(DateTime when, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final today = _dateOnly(ref);
    final day = _dateOnly(when);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return NoteDaySection.today;
    if (diff == 1) return NoteDaySection.yesterday;
    if (diff < 7) return NoteDaySection.thisWeek;
    return NoteDaySection.older;
  }

  /// Compact relative stamp for cards, e.g. `3:04 PM`, `Yesterday`, `Mon`,
  /// `12 Jun`, `12 Jun 2024`.
  static String relative(DateTime when, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final section = sectionFor(when, now: ref);
    switch (section) {
      case NoteDaySection.today:
        return DateFormat.jm().format(when);
      case NoteDaySection.yesterday:
        return 'Yesterday';
      case NoteDaySection.thisWeek:
        return DateFormat.E().format(when); // Mon, Tue…
      case NoteDaySection.older:
        return when.year == ref.year
            ? DateFormat('d MMM').format(when)
            : DateFormat('d MMM yyyy').format(when);
    }
  }

  /// Full stamp for the editor footer, e.g. `Edited 12 Jun 2025, 3:04 PM`.
  static String fullEdited(DateTime when) =>
      'Edited ${DateFormat('d MMM yyyy, h:mm a').format(when)}';

  /// Full creation stamp, e.g. `Created 12 Jun 2025, 3:04 PM`.
  static String fullCreated(DateTime when) =>
      'Created ${DateFormat('d MMM yyyy, h:mm a').format(when)}';

  /// Bare date-time stamp, e.g. `12 Jun 2025, 3:04 PM` (used for reminders).
  static String stamp(DateTime when) =>
      DateFormat('d MMM yyyy, h:mm a').format(when);

  /// Date-only stamp for the editor "insert date" action, e.g. `12 Jun 2025`.
  static String dateStamp(DateTime when) =>
      DateFormat('d MMM yyyy').format(when);

  /// Time-only stamp for the editor "insert time" action, e.g. `3:04 PM`.
  static String timeStamp(DateTime when) => DateFormat.jm().format(when);

  /// Groups an already-sorted list into day sections, preserving order.
  static Map<NoteDaySection, List<Note>> groupByDay(
    List<Note> notes, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final map = <NoteDaySection, List<Note>>{};
    for (final n in notes) {
      final section = sectionFor(n.updatedAt, now: ref);
      (map[section] ??= <Note>[]).add(n);
    }
    return map;
  }
}

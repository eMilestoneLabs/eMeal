/// Live-Test-16 ISSUE-14 — shared bounds for report / billing date pickers.
///
/// Retention purges a group's history beyond its retained billing cycles, so
/// offering older dates only ever returns empty data. The earliest pickable
/// day is the group's server-derived `dataAvailableFrom`, never earlier than
/// the pickers' previous 365-day window (unknown → that window, unchanged).
///
/// Flutter's date pickers ASSERT when an initial date/range lies outside
/// [firstDate, lastDate]; [clampDay] / [clampRange] keep a previously
/// selected (possibly older) range valid so opening a picker can never crash.
class ReportDateBounds {
  const ReportDateBounds._();

  static const Duration _defaultLookback = Duration(days: 365);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Earliest selectable day.
  static DateTime firstPickable(DateTime? dataAvailableFrom, {DateTime? now}) {
    final fallback = _day((now ?? DateTime.now()).subtract(_defaultLookback));
    if (dataAvailableFrom == null) return fallback;
    final floor = _day(dataAvailableFrom);
    return floor.isAfter(fallback) ? floor : fallback;
  }

  /// [d] clamped into [first, last].
  static DateTime clampDay(DateTime d, DateTime first, DateTime last) {
    if (d.isBefore(first)) return first;
    if (d.isAfter(last)) return last;
    return d;
  }

  /// Both ends clamped into [first, last] (end never before start).
  static (DateTime, DateTime) clampRange(
      DateTime start, DateTime end, DateTime first, DateTime last) {
    final s = clampDay(start, first, last);
    final e = clampDay(end, first, last);
    return (s, e.isBefore(s) ? s : e);
  }
}

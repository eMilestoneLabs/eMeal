import 'package:smart_meal_management/core/utils/name_display.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

/// One resolved (member × meal × day) attendance line used by exports + billing.
///
/// Rows are produced from the real attendance records, with gaps filled by
/// **virtual auto-skip** (req 6): when a member did not mark a meal whose window
/// has already closed, the row is a Skipped entry stamped with the meal's
/// closing time — no DB writes, computed at report time.
class BillingRow {
  const BillingRow({
    required this.userId,
    required this.userName,
    required this.mealId,
    required this.mealName,
    required this.status,
    required this.preference,
    required this.price,
    required this.date,
    required this.markedAt,
    required this.autoSkipped,
    this.billAbsent,
  });

  final String userId;
  final String userName;
  final String mealId;
  final String mealName;
  final AttendanceStatus status;
  final String? preference;
  final int? price;
  final DateTime date;
  final DateTime? markedAt;

  /// True when this row was synthesised (member never marked, window closed).
  final bool autoSkipped;

  /// Live-Test-11 ISSUE-017: server write-time Bill-Absent snapshot — true
  /// only on an absent row that bills. Null on virtual rows / old records.
  final bool? billAbsent;

  bool get isPresent => status == AttendanceStatus.present;

  /// Module 36 (FR-PG-052): structured selection display for exports —
  /// "Staple: Ruti · Non-Veg: Mutton ×2". Falls back to the legacy flat
  /// preference when the record predates preference groups.
  static String? selectionDisplay(AttendanceModel r) {
    final snap = r.preferences;
    if (snap == null || snap.isEmpty) return r.preference;
    final parts = <String>[];
    for (final e in snap) {
      if (e is! Map) continue;
      final group = e['groupLabel']?.toString() ?? '';
      final option = e['optionLabel']?.toString() ?? '';
      final qty = (e['quantity'] as num?)?.toInt() ?? 1;
      if (option.isEmpty) continue;
      parts.add(
          '${group.isNotEmpty ? '$group: ' : ''}$option${qty > 1 ? ' ×$qty' : ''}');
    }
    return parts.isEmpty ? r.preference : parts.join(' · ');
  }
}

/// Per-member billing + attendance totals for the export summary + billing screen.
class BillingSummary {
  const BillingSummary({
    required this.userId,
    required this.userName,
    required this.present,
    required this.absent,
    required this.skipped,
    required this.totalBill,
    required this.consumedByMeal,
  });

  final String userId;
  final String userName;
  final int present;
  final int absent;
  final int skipped;

  /// Total payable = sum of price over PRESENT rows only.
  final int totalBill;

  /// mealName -> present (consumed) count.
  final Map<String, int> consumedByMeal;

  int get totalMeals => present + absent + skipped;
}

/// Computes export/billing rows + summaries from raw attendance + meal prices.
///
/// Reuses the existing attendance records (no new contract). Only meals that are
/// active and non-virtual are billed; the implicit general-attendance slot
/// (price null) still appears but never contributes to the bill.
class BillingService {
  BillingService._();

  /// Builds the full (member × meal × day) grid for [from]..[to], filling
  /// un-marked closed windows with virtual Skipped @ closeTime.
  static List<BillingRow> buildRows({
    required List<AttendanceModel> records,
    required List<MealModel> meals,
    required DateTime from,
    required DateTime to,
    DateTime? now,
    List<MealModel> todayMeals = const [],
    Set<String> vacationUserIds = const {},
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);

    final activeMeals = meals.where((m) => m.isActive).toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Issue 3: for TODAY, the effective attendance window + price come from the
    // active published planner (Weekly / Day-Wise Meal Mode), which can differ
    // from the master meal catalogue. Using the master close time made the
    // virtual auto-skip fire while today's per-day window was still open. When
    // today's overlay meals are supplied, prefer them for the current day so a
    // skip is only ever synthesised AFTER the real window has closed.
    final todayById = {for (final m in todayMeals) m.id: m};
    if (activeMeals.isEmpty) {
      // No meal catalogue — fall back to the raw records as-is.
      return records
          .map((r) => BillingRow(
                userId: r.userId,
                userName: displayMemberName(r.userName),
                mealId: r.mealId,
                mealName: r.mealName ?? '—',
                status: r.status,
                preference: BillingRow.selectionDisplay(r),
                price: null,
                date: DateTime(r.date.year, r.date.month, r.date.day),
                markedAt: r.markedAt,
                autoSkipped: false,
              ))
          .toList();
    }

    // Distinct members from the records (those who marked at least once).
    final memberNames = <String, String>{};
    for (final r in records) {
      memberNames[r.userId] = displayMemberName(r.userName);
    }

    // (userId|mealId|yyyy-mm-dd) -> record
    String key(String uid, String mid, DateTime d) =>
        '$uid|$mid|${_ymd(d)}';
    final recByKey = <String, AttendanceModel>{};
    for (final r in records) {
      recByKey[key(r.userId, r.mealId,
          DateTime(r.date.year, r.date.month, r.date.day))] = r;
    }

    final fromD = DateTime(from.year, from.month, from.day);
    final toD = DateTime(to.year, to.month, to.day);

    final rows = <BillingRow>[];
    for (final entry in memberNames.entries) {
      final uid = entry.key;
      final uname = entry.value;
      for (var d = fromD;
          !d.isAfter(toD);
          d = d.add(const Duration(days: 1))) {
        if (d.isAfter(today)) break; // future days have no attendance yet
        final isToday = d.isAtSameMomentAs(today);
        for (final meal in activeMeals) {
          // For today, use the published per-day window/price when available.
          final effectiveMeal =
              isToday ? (todayById[meal.id] ?? meal) : meal;
          final rec = recByKey[key(uid, meal.id, d)];
          final closeDt =
              _closeDateTime(d, effectiveMeal.attendanceWindow.closeTime);
          final windowClosed = d.isBefore(today) ||
              (isToday && closeDt != null && clock.isAfter(closeDt));

          if (rec != null) {
            // Real record. A skipped record without a markedAt uses closeTime.
            final marked = (rec.status == AttendanceStatus.skipped &&
                    rec.markedAt == null)
                ? closeDt
                : rec.markedAt;
            rows.add(BillingRow(
              userId: uid,
              userName: uname,
              mealId: meal.id,
              mealName: meal.name,
              status: rec.status,
              preference: BillingRow.selectionDisplay(rec),
              // Per-day price snapshot overrides master; fall back to the
              // day-effective price for legacy records marked before pricing.
              price: rec.price ?? effectiveMeal.price,
              date: d,
              markedAt: marked,
              autoSkipped: false,
              // ISSUE-017: the record's own snapshot rides through so the
              // client bill matches the server engine row for row.
              billAbsent: rec.billAbsent,
            ));
          } else if (windowClosed && !vacationUserIds.contains(uid)) {
            // Virtual auto-skip (req 6): member never marked, window closed.
            // Issue 7: members currently on Vacation Mode are excluded from
            // attendance calculations — never synthesise a skip for them.
            rows.add(BillingRow(
              userId: uid,
              userName: uname,
              mealId: meal.id,
              mealName: meal.name,
              status: AttendanceStatus.skipped,
              preference: null,
              price: effectiveMeal.price,
              date: d,
              markedAt: closeDt,
              autoSkipped: true,
            ));
          }
          // else: window still open today -> pending, not yet a row.
        }
      }
    }

    // ISSUE-001 (Live-Test-13): the loop above walks the ACTIVE meal catalogue
    // and looks records up by meal id, so a REAL record whose master meal was
    // later disabled or deleted is never looked up and never emitted — the line
    // silently vanished from billing, exports and the student bill while the
    // row still existed in the database (verified in prod: archived meals still
    // held their attendance rows). Because each day's shown total is summed
    // from these rows, the total stayed self-consistent, which is why it looked
    // like "entry gone but bill unchanged".
    //
    // Historical billing is permanent, so those records are restored here from
    // the record's OWN immutable snapshot (name + price captured at mark time).
    // Only REAL records are recovered — a virtual auto-skip is never
    // synthesised for an archived meal, since a meal that no longer runs must
    // not invent new charges.
    final activeIds = {for (final m in activeMeals) m.id};
    for (final r in records) {
      if (activeIds.contains(r.mealId)) continue;
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      if (d.isBefore(fromD) || d.isAfter(toD)) continue;
      rows.add(BillingRow(
        userId: r.userId,
        userName: displayMemberName(r.userName),
        mealId: r.mealId,
        mealName: r.mealName ?? '—',
        status: r.status,
        preference: BillingRow.selectionDisplay(r),
        price: r.price,
        date: d,
        markedAt: r.markedAt,
        autoSkipped: false,
        billAbsent: r.billAbsent,
      ));
    }

    // Stable ordering: member, then date, then meal order.
    // Archived meals are absent from [order]; they sort last within their day
    // (fallback index) instead of being interleaved by a stale position.
    final order = {for (var i = 0; i < activeMeals.length; i++) activeMeals[i].id: i};
    rows.sort((a, b) {
      final n = a.userName.toLowerCase().compareTo(b.userName.toLowerCase());
      if (n != 0) return n;
      final dt = a.date.compareTo(b.date);
      if (dt != 0) return dt;
      return (order[a.mealId] ?? activeMeals.length)
          .compareTo(order[b.mealId] ?? activeMeals.length);
    });
    return rows;
  }

  /// Aggregates [rows] into per-member billing summaries.
  ///
  /// Live-Test-8 ISSUE-005 (server-engine parity):
  ///   • present → always billed;
  ///   • skipped → always billed — a REAL `skipped` record exists only for a
  ///     date whose Bill-Skip policy was ON at window-close (the server sweep
  ///     is the only writer), so its existence IS the date-forward gate; the
  ///     current flag must NOT be consulted (flipping Bill-Skip off never
  ///     un-bills already-closed skips);
  ///   • absent → bills ONLY when its per-record `billAbsent` snapshot is
  ///     true (Live-Test-11 ISSUE-017: the server stamps the independent
  ///     Bill-Absent toggle onto each absent row at write time — the row
  ///     carries its own date-forward gate, exactly like Bill-Skip).
  /// [billSkippedMeals]/[billAbsentMeals] are retained for call-site
  /// compatibility but no longer affect the math (matches the server's
  /// BillingService.billedAttendanceFilter()).
  static List<BillingSummary> summarize(
    List<BillingRow> rows, {
    bool billSkippedMeals = false,
    bool? billAbsentMeals,
  }) {
    final byUser = <String, List<BillingRow>>{};
    final names = <String, String>{};
    for (final r in rows) {
      byUser.putIfAbsent(r.userId, () => []).add(r);
      names[r.userId] = r.userName;
    }
    final out = <BillingSummary>[];
    byUser.forEach((uid, list) {
      int present = 0, absent = 0, skipped = 0, bill = 0;
      final consumed = <String, int>{};
      for (final r in list) {
        switch (r.status) {
          case AttendanceStatus.present:
            present++;
            bill += r.price ?? 0;
            consumed[r.mealName] = (consumed[r.mealName] ?? 0) + 1;
          // Live-Test-6 ISSUE-4 (billing display parity): only REAL attendance
          // records are ever billed — the backend billing engine bills the
          // system-generated Skip records its close-time sweep writes, never
          // the client's virtual placeholder rows (autoSkipped). Billing the
          // placeholders here inflated the detail/export total for the whole
          // period grid (e.g. ₹5435 vs the engine's ₹180).
          case AttendanceStatus.absent:
            absent++;
            // Live-Test-11 ISSUE-017 (server-engine parity): an absent bills
            // ONLY when its own write-time snapshot says the Bill-Absent
            // toggle was ON — identical date-forward rule to the backend
            // engine; the CURRENT flag is never consulted.
            if (r.billAbsent == true) bill += r.price ?? 0;
          case AttendanceStatus.skipped:
            skipped++;
            // Real skipped records always bill (policy was ON when they were
            // written); virtual placeholders (autoSkipped) never bill.
            if (!r.autoSkipped) bill += r.price ?? 0;
          default:
            break;
        }
      }
      out.add(BillingSummary(
        userId: uid,
        userName: names[uid] ?? uid,
        present: present,
        absent: absent,
        skipped: skipped,
        totalBill: bill,
        consumedByMeal: consumed,
      ));
    });
    out.sort((a, b) =>
        a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));
    return out;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Combines a date with an "HH:mm" close time into a DateTime, or null.
  static DateTime? _closeDateTime(DateTime day, String closeTime) {
    final parts = closeTime.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateTime(day.year, day.month, day.day, h, m);
  }
}

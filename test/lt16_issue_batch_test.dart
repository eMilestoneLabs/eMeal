// Issues_Live_Test_16 — regression guards for the Flutter side of the batch.
// Pure logic only (no widgets, no platform channels, no network).
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/utils/report_date_bounds.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/features/admin/billing/providers/member_billing_provider.dart';
import 'package:smart_meal_management/features/notepad/models/note.dart';
import 'package:smart_meal_management/features/notepad/utils/note_date_format.dart';
import 'package:smart_meal_management/features/student/settings/utils/vacation_today_availability.dart';
import 'package:smart_meal_management/shared/enums/user_role.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/billing_summary.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

MealModel _meal(String id, String slot, int order,
        {String open = '07:00',
        String close = '09:00',
        String? state,
        int? orgClock,
        bool active = true}) =>
    MealModel(
      id: id,
      groupId: 'g1',
      organizationId: 'org1',
      name: slot,
      slotKey: slot,
      order: order,
      attendanceWindow: MealAttendanceWindow(openTime: open, closeTime: close),
      isActive: active,
      windowState: state,
      orgClockMinutes: orgClock,
      orgDate: '2026-09-27',
    );

AttendanceModel _rec(String mealId, AttendanceStatus s,
        {String user = 'u1', DateTime? date, List<dynamic>? prefs}) =>
    AttendanceModel(
      id: 'r_$mealId',
      mealId: mealId,
      userId: user,
      groupId: 'g1',
      organizationId: 'org1',
      status: s,
      date: date ?? DateTime(2026, 9, 27),
      preferences: prefs,
      userName: user,
    );

BillingRow _row(String user, String meal, DateTime d) => BillingRow(
      userId: user,
      userName: user,
      mealId: meal,
      mealName: meal,
      status: AttendanceStatus.present,
      preference: null,
      price: null,
      date: d,
      markedAt: null,
      autoSkipped: false,
    );

BillingMemberRow _member(String name, int net, int present) => BillingMemberRow(
      userId: name,
      userName: name,
      role: 'student',
      totalBill: net,
      netBill: net,
      presentCount: present,
      skippedCount: 0,
      absentCount: 0,
    );

void main() {
  // ── ISSUE-2: vacation only for UPCOMING meals ─────────────────────────────
  group('VacationTodayAvailability (ISSUE-2)', () {
    // Org clock 13:00 (780 min): breakfast 07–09 closed, lunch 12–14 open,
    // dinner 19–22 upcoming.
    final meals = [
      _meal('b', 'breakfast', 1, open: '07:00', close: '09:00', orgClock: 780),
      _meal('l', 'lunch', 2, open: '12:00', close: '14:00', orgClock: 780),
      _meal('d', 'dinner', 3, open: '19:00', close: '22:00', orgClock: 780),
    ];
    final fetched = DateTime.now();

    test('past windows and taken meals are blocked; whole day hidden', () {
      final a = VacationTodayAvailability.compute(
        todayMeals: meals,
        myTodayRecords: [_rec('l', AttendanceStatus.present)],
        fetchedAt: fetched,
      );
      expect(a.blockedSlotKeys, {'breakfast', 'lunch'});
      expect(a.upcomingSlotKeys, {'dinner'});
      expect(a.wholeDayTodayAllowed, isFalse);
      expect(a.hasUpcomingToday, isTrue);
      expect(a.orgToday, DateTime(2026, 9, 27));
    });

    test('nothing decided yet → whole day allowed', () {
      final early = [
        for (final m in meals)
          _meal(m.id, m.slotKey, m.order,
              open: m.attendanceWindow.openTime,
              close: m.attendanceWindow.closeTime,
              orgClock: 360), // 06:00
      ];
      final a = VacationTodayAvailability.compute(
        todayMeals: early,
        myTodayRecords: const [],
        fetchedAt: fetched,
      );
      expect(a.blockedSlotKeys, isEmpty);
      expect(a.wholeDayTodayAllowed, isTrue);
    });

    test('everything past/taken → today not available (start tomorrow)', () {
      final a = VacationTodayAvailability.compute(
        todayMeals: meals,
        myTodayRecords: [
          _rec('l', AttendanceStatus.absent),
          _rec('d', AttendanceStatus.present),
        ],
        fetchedAt: fetched,
      );
      expect(a.upcomingSlotKeys, isEmpty);
      expect(a.hasUpcomingToday, isFalse);
    });

    test('server verdict "closed" wins even before the clock says so', () {
      final a = VacationTodayAvailability.compute(
        todayMeals: [_meal('d', 'dinner', 3, state: 'closed', orgClock: 60)],
        myTodayRecords: const [],
        fetchedAt: fetched,
      );
      expect(a.blockedSlotKeys, {'dinner'});
    });
  });

  // ── ISSUE-5: saved preference picks rebuilt from the snapshot ────────────
  test('AttendanceModel.savedSelections rebuilds picks (ISSUE-5)', () {
    final r = _rec('m', AttendanceStatus.present, prefs: [
      {'groupId': 'pg1', 'optionKey': 'chicken', 'quantity': 2},
      {'groupId': 'pg2', 'optionKey': 'dal'},
      {'groupLabel': 'legacy-no-ids'},
      'not-a-map',
    ]);
    final s = r.savedSelections;
    expect(s.map((e) => '${e.groupId}:${e.optionKey}:${e.quantity}'),
        ['pg1:chicken:2', 'pg2:dal:1']);
    expect(_rec('m', AttendanceStatus.present).savedSelections, isEmpty);
  });

  // ── ISSUE-6: notepad sections follow the active sort ─────────────────────
  test('groupByDay buckets by the sort timestamp (ISSUE-6)', () {
    final now = DateTime(2026, 9, 27, 12);
    final n = Note(
      id: 'n1',
      title: 't',
      body: 'b',
      createdAt: DateTime(2026, 9, 1), // older
      updatedAt: DateTime(2026, 9, 27, 9), // today
    );
    expect(NoteDateFormat.groupByDay([n], now: now).keys.single,
        NoteDaySection.today);
    expect(
        NoteDateFormat.groupByDay([n], now: now, dateOf: (x) => x.createdAt)
            .keys
            .single,
        NoteDaySection.older);
  });

  // ── ISSUE-4: guest config normalisation ──────────────────────────────────
  test('GroupGuestConfig: retired mode → sameAsMember, cap clamped (ISSUE-4)',
      () {
    final legacy = GroupGuestConfig.fromJson({
      'guestPricingMode': 'perGuestPrice',
      'maxGuestsPerMemberPerMeal': 10,
      'guestAdultPrice': 80,
      'guestChildPrice': 40,
    });
    expect(legacy.guestPricingMode, 'sameAsMember');
    expect(legacy.maxGuestsPerMemberPerMeal, AppConstants.guestMaxPerMeal);
    // Adult and child now price identically (member price).
    expect(
        legacy.estimatePrice(mealPrice: 60, isAdult: true, pricingEnabled: true),
        60);
    expect(
        legacy.estimatePrice(mealPrice: 60, isAdult: false, pricingEnabled: true),
        60);
    final surcharge = GroupGuestConfig.fromJson({
      'guestPricingMode': 'flatSurcharge',
      'guestSurcharge': 15,
    });
    expect(surcharge.guestPricingMode, 'flatSurcharge');
    expect(
        surcharge.estimatePrice(
            mealPrice: 60, isAdult: false, pricingEnabled: true),
        75);
  });

  // ── ISSUE-12: member billing sorts (Newest/Oldest removed) ───────────────
  group('MemberBillingProvider sorting (ISSUE-12)', () {
    MemberBillingProvider provider() => MemberBillingProvider()
      ..summary = BillingSummaryV2(
        revenue: 0,
        memberCount: 3,
        presentMeals: 0,
        skippedMeals: 0,
        absentMeals: 0,
        averageBill: 0,
        mealBreakdown: const [],
        members: [
          _member('Charlie', 100, 3),
          _member('alice', 100, 5),
          _member('Bob', 300, 1),
        ],
      );

    test('only the five meaningful sorts remain', () {
      expect(BillingSort.values.map((e) => e.name),
          ['highestBill', 'lowestBill', 'mostMeals', 'leastMeals', 'name']);
    });

    test('ties fall back to name (stable order)', () {
      final p = provider()..sort = BillingSort.highestBill;
      expect(p.visibleMembers.map((m) => m.userName),
          ['Bob', 'alice', 'Charlie']);
      p.sort = BillingSort.lowestBill;
      expect(p.visibleMembers.map((m) => m.userName),
          ['alice', 'Charlie', 'Bob']);
      p.sort = BillingSort.mostMeals;
      expect(p.visibleMembers.first.userName, 'alice');
      p.sort = BillingSort.name;
      expect(p.visibleMembers.map((m) => m.userName),
          ['alice', 'Bob', 'Charlie']);
    });
  });

  // ── ISSUE-15: role labels ────────────────────────────────────────────────
  test('UserRole.labelOf shows Title Case with spaces (ISSUE-15)', () {
    expect(UserRole.labelOf('hostelManager'), 'Hostel Manager');
    expect(UserRole.labelOf('messManager'), 'Mess Manager');
    expect(UserRole.labelOf('student'), 'Student');
    expect(UserRole.labelOf('somethingNew'), 'somethingNew');
  });

  // ── ISSUE-17: date-wise report order ─────────────────────────────────────
  test('sortDateFirst orders date → meal order → member (ISSUE-17)', () {
    final meals = [_meal('dn', 'dinner', 2), _meal('bf', 'breakfast', 1)];
    final rows = [
      _row('zed', 'dn', DateTime(2026, 9, 2)),
      _row('amy', 'dn', DateTime(2026, 9, 1)),
      _row('zed', 'bf', DateTime(2026, 9, 1)),
      _row('amy', 'bf', DateTime(2026, 9, 1)),
      // A LATER-day breakfast must still come after an earlier-day dinner —
      // only a genuinely date-first order satisfies this.
      _row('amy', 'bf', DateTime(2026, 9, 2)),
    ];
    final out = BillingService.sortDateFirst(rows, meals);
    expect(out.map((r) => '${r.date.day}:${r.mealId}:${r.userName}'), [
      '1:bf:amy',
      '1:bf:zed',
      '1:dn:amy',
      '2:bf:amy',
      '2:dn:zed',
    ]);
    expect(rows.first.userName, 'zed', reason: 'input list is not mutated');
  });

  test('buildRows fallback (no meal catalogue) is sorted member → date', () {
    final out = BillingService.buildRows(
      records: [
        _rec('x', AttendanceStatus.present,
            user: 'b', date: DateTime(2026, 9, 3)),
        _rec('x', AttendanceStatus.present,
            user: 'a', date: DateTime(2026, 9, 5)),
        _rec('x', AttendanceStatus.present,
            user: 'a', date: DateTime(2026, 9, 1)),
      ],
      meals: const [],
      from: DateTime(2026, 9, 1),
      to: DateTime(2026, 9, 5),
    );
    expect(out.map((r) => '${r.userId}:${r.date.day}'), ['a:1', 'a:5', 'b:3']);
  });

  // ── ISSUE-14: picker bounds never crash, never offer purged dates ───────
  group('ReportDateBounds (ISSUE-14)', () {
    final now = DateTime(2026, 9, 27);
    test('floor wins when later than the 365-day default', () {
      expect(ReportDateBounds.firstPickable(DateTime(2026, 7, 1), now: now),
          DateTime(2026, 7, 1));
    });
    test('unknown floor keeps the previous 365-day window', () {
      expect(ReportDateBounds.firstPickable(null, now: now),
          DateTime(2025, 9, 27));
    });
    test('an older initial range is clamped inside the bounds', () {
      final (s, e) = ReportDateBounds.clampRange(DateTime(2026, 1, 1),
          DateTime(2026, 2, 1), DateTime(2026, 7, 1), now);
      expect(s, DateTime(2026, 7, 1));
      expect(e, DateTime(2026, 7, 1));
    });
  });

  // ── ISSUE-16: itemised adjustments ───────────────────────────────────────
  test('ExportAdjustment: sign, units and labels (ISSUE-16)', () {
    final credit = ExportAdjustment.fromApi({
      'userId': 'u1',
      'entryDate': '2026-09-20',
      'type': 'credit',
      'amount': 12550,
      'reason': 'Advance paid',
      'status': 'posted',
    });
    expect(credit.amountLabel('Rs '), '-Rs 125.50');
    expect(credit.dateLabel, '20/09/2026');
    expect(credit.typeLabel, 'Credit');
    final refund = ExportAdjustment.fromApi({
      'type': 'refund',
      'amount': 5000,
      'entryDate': '2026-09-21',
    });
    expect(refund.amountLabel('₹'), '+₹50.00');
    expect(refund.statusLabel, 'Posted');
  });
}

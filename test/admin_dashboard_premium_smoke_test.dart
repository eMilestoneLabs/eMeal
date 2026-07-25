// Live-Test-10 runtime regression guard for the Admin Dashboard.
//
// Renders the REAL AdminDashboardScreen (real _MealSummaryCard, _CountPill
// grid, vibrant AppAnalyticsCard tiles, group switcher, activity, group
// tiles) with rich fixture data in BOTH themes across FOUR screen sizes,
// scrolling every section into view and asserting zero runtime exceptions.
//
// Exists because the gray-box regression (Expanded inside Wrap) was invisible
// to `flutter analyze` — only an actual render catches that failure class.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/core/theme/app_theme.dart';
import 'package:smart_meal_management/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:smart_meal_management/features/admin/dashboard/screens/admin_dashboard_screen.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_attendance_summary.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

const _groupA = GroupModel(
  id: 'g1',
  organizationId: 'org1',
  name: 'Midnapore Namaste Mess',
  type: GroupType.mess,
  mealConfig: GroupMealConfig(mealsEnabled: true),
  memberIds: ['u1', 'u2', 'u3'],
);

const _groupB = GroupModel(
  id: 'g2',
  organizationId: 'org1',
  name: 'North Wing Hostel',
  type: GroupType.hostel,
  mealConfig: GroupMealConfig(mealsEnabled: true),
  memberIds: ['u4', 'u5'],
);

MealModel _meal(String id, String name, String slotKey, int order,
        {int? price}) =>
    MealModel(
      id: id,
      groupId: 'g1',
      organizationId: 'org1',
      name: name,
      slotKey: slotKey,
      order: order,
      attendanceWindow:
          const MealAttendanceWindow(openTime: '07:00', closeTime: '09:00'),
      isActive: true,
      price: price,
    );

final _breakfast = _meal('m1', 'Breakfast', 'breakfast', 1, price: 50);
final _lunch = _meal('m2', 'Lunch', 'lunch', 2, price: 100);

/// Breakfast: the "everything on" card — vacation, live pending, guests,
/// member + guest preference-group sections. Exercises every pill branch.
const _breakfastSummary = MealAttendanceSummary(
  mealId: 'm1',
  slotKey: 'breakfast',
  mealName: 'Breakfast',
  date: '2026-07-18',
  totalMembers: 3,
  presentCount: 2,
  absentCount: 0,
  skippedCount: 1,
  preferenceBreakdown: {'chicken': 1, 'milk': 1},
  snapshotPrice: 50,
  guestCount: 2,
  guestAdults: 1,
  guestChildren: 1,
  attendingTotal: 4,
  expectedParticipants: 3,
  preferenceGroupBreakdown: {
    'Option 2': {'Boil Egg': 1, 'Milk': 1},
    'Option 3': {'Pareta': 3, 'Ruti': 3},
  },
  vacationCount: 1,
  pendingCount: 1,
  guestPreferenceGroupBreakdown: {
    'Option 2': {'Milk': 2},
  },
  // Kitchen Summary (Live-Test-10): 2 approved + 2 awaiting + 1 cancelled +
  // 1 no-show. Option 2 totals 4 (= present 2 + guests 2) → green ✓.
  // ISSUE-006 (Live-Test-13): the mismatch rule changed — an UNDER-count is
  // now absorbed as the hidden system NONE ("Historical NULL / legacy
  // attendance"), so only an OVER-count still reds. Option 3 totals 6 > 4,
  // i.e. a selection exists for somebody who is not attending — the one
  // genuine integrity fault the banner must still catch.
  guestPendingApproval: 2,
  guestCancelled: 1,
  guestNoShow: 1,
  guestTotalRequests: 6,
);

/// Lunch: minimal standalone card — flat guest preferences only.
const _lunchSummary = MealAttendanceSummary(
  mealId: 'm2',
  slotKey: 'lunch',
  mealName: 'Lunch',
  date: '2026-07-18',
  totalMembers: 3,
  presentCount: 3,
  absentCount: 0,
  skippedCount: 0,
  // Standalone mode, fully valid: members 2+1 + guest 1 = 4 = present 3 +
  // approved guest 1 → the green “Total 4 ✓” chip path.
  preferenceBreakdown: {'rice': 2, 'roti': 1},
  guestCount: 1,
  guestAdults: 1,
  attendingTotal: 4,
  expectedParticipants: 3,
  guestPreferenceBreakdown: {'veg': 1},
  guestTotalRequests: 1,
);

final _activity = [
  AttendanceModel(
    id: 'a1',
    mealId: 'm1',
    userId: 'u1',
    groupId: 'g1',
    organizationId: 'org1',
    status: AttendanceStatus.present,
    date: DateTime(2026, 7, 18),
    markedAt: DateTime(2026, 7, 18, 8, 5),
    userName: 'Suravi Mukherjee',
    mealName: 'Breakfast',
  ),
  AttendanceModel(
    id: 'a2',
    mealId: 'm2',
    userId: 'u2',
    groupId: 'g1',
    organizationId: 'org1',
    status: AttendanceStatus.absent,
    date: DateTime(2026, 7, 18),
    markedAt: DateTime(2026, 7, 18, 8, 10),
    userName: 'Reena Prasad',
    mealName: 'Lunch',
  ),
];

/// Overrides every public read the screen performs; load() is never invoked
/// because the fake AuthProvider has no session (currentUser == null).
class _FakeDashboardProvider extends AdminDashboardProvider {
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  List<GroupModel> get groups => [_groupA, _groupB];
  @override
  DateTime? get lastUpdated =>
      DateTime.now().subtract(const Duration(minutes: 10));
  @override
  List<MealModel> get todayMeals => [_breakfast, _lunch];
  @override
  String get adminName => 'Soumyakanti Mal';
  @override
  String get orgName => 'Midnapore Namaste Mess';
  @override
  String? get selectedGroupId => 'g1';
  @override
  GroupModel? get selectedGroup => _groupA;
  @override
  int get totalMembers => 3;
  @override
  int get presentToday => 5;
  @override
  int get absentToday => 0;
  @override
  double get attendanceRate => 0.83;
  @override
  List<MealModel> get selectedGroupTodayMeals => [_breakfast, _lunch];
  @override
  MealAttendanceSummary? mealSummary(String mealId) => switch (mealId) {
        'm1' => _breakfastSummary,
        'm2' => _lunchSummary,
        _ => null,
      };
  @override
  List<AttendanceModel> get recentActivity => _activity;
}

// ── Harness ─────────────────────────────────────────────────────────────────

/// Labels that must appear at least once while the list scrolls through the
/// viewport (ListView disposes off-screen children, so presence is recorded
/// per-frame rather than asserted at the end).
const _mustSee = <String>{
  'Overview',
  'Total Members',
  'Present',
  'Skip',
  'Vacation',
  'Pending',
  'Your Groups',
  'North Wing Hostel',
};

/// Substring targets (chips/banners whose full text embeds counts).
const _mustContain = <String>{
  'GUEST SUMMARY',
  'Approved / Present',
  'Awaiting Approval',
  'Cancelled / Rejected',
  'TOTAL TO SERVE',
  'Standalone Preference',
  'Total 4 ✓',
  'Dashboard Data Mismatch',
};

Future<Set<String>> _pumpDashboard(
  WidgetTester tester, {
  required ThemeData theme,
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: AuthProviderScope(
        provider: AuthProvider(),
        child: AdminDashboardScope(
          notifier: _FakeDashboardProvider(),
          child: const AdminDashboardScreen(),
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull,
      reason: 'first frame must render without any runtime exception');

  final seen = <String>{};
  void record() {
    for (final label in _mustSee) {
      if (find.text(label).evaluate().isNotEmpty) seen.add(label);
    }
    for (final part in _mustContain) {
      if (find.textContaining(part).evaluate().isNotEmpty) seen.add(part);
    }
  }

  record();

  // Drag every section through the viewport — lazily-built ListView children
  // (meal cards, quick actions, activity, group tiles) all get laid out.
  final list = find.byType(ListView).first;
  for (var i = 0; i < 14; i++) {
    await tester.drag(list, const Offset(0, -350));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'scroll segment $i must lay out without exceptions');
    record();
  }
  return seen;
}

void main() {
  const sizes = <String, Size>{
    'small phone': Size(320, 640),
    'large phone': Size(412, 915),
    'tablet': Size(800, 1280),
    'landscape': Size(915, 412),
  };

  for (final entry in sizes.entries) {
    testWidgets('renders premium dashboard · light · ${entry.key}',
        (tester) async {
      final seen = await _pumpDashboard(tester,
          theme: AppTheme.light, size: entry.value);
      // Every section + every count-pill branch scrolled through the
      // viewport and rendered.
      expect(seen, containsAll({..._mustSee, ..._mustContain}));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('renders premium dashboard · dark · ${entry.key}',
        (tester) async {
      final seen = await _pumpDashboard(tester,
          theme: AppTheme.dark, size: entry.value);
      expect(seen, containsAll({..._mustSee, ..._mustContain}));
      await tester.binding.setSurfaceSize(null);
    });
  }
}

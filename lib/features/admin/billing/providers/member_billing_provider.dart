import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/shared/models/billing_series.dart';
import 'package:smart_meal_management/shared/models/billing_summary.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/models/user_model.dart';

enum BillingPeriod { today, week, month, custom }

enum BillingSort {
  highestBill,
  lowestBill,
  mostMeals,
  leastMeals,
  name,
  newest,
  oldest,
}

enum BillingBucket { day, week, month }

/// State manager for Member Billing V2 (admin). Loads the group-wide billing
/// aggregate from the backend and exposes period / group / sort / search.
class MemberBillingProvider extends ChangeNotifier {
  MemberBillingProvider({
    AttendanceRepository? attendanceRepo,
    GroupRepository? groupRepo,
  })  : _attendanceRepo = attendanceRepo ?? AttendanceRepository(),
        _groupRepo = groupRepo ?? GroupRepository();

  final AttendanceRepository _attendanceRepo;
  final GroupRepository _groupRepo;

  bool loadingGroups = true;
  bool loading = false;
  String? error;

  List<GroupModel> groups = [];
  String? groupId;

  BillingPeriod period = BillingPeriod.month;
  DateTime from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime to = DateTime.now();

  BillingSort sort = BillingSort.highestBill;
  String search = '';

  BillingSummaryV2 summary = BillingSummaryV2.empty;

  BillingBucket bucket = BillingBucket.day;
  BillingSeries series = BillingSeries.empty;

  String _organizationId = '';

  GroupModel? get selectedGroup {
    if (groupId == null) return null;
    for (final g in groups) {
      if (g.id == groupId) return g;
    }
    return null;
  }

  bool get pricingEnabled =>
      selectedGroup?.mealConfig.mealPricingEnabled ?? false;

  List<BillingMemberRow> get visibleMembers {
    final q = search.trim().toLowerCase();
    final list = q.isEmpty
        ? List<BillingMemberRow>.from(summary.members)
        : summary.members
            .where((m) =>
                m.userName.toLowerCase().contains(q) ||
                m.role.toLowerCase().contains(q) ||
                m.userId.toLowerCase().contains(q) ||
                (m.email?.toLowerCase().contains(q) ?? false) ||
                (m.phone?.toLowerCase().contains(q) ?? false))
            .toList();

    int byDate(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b);
    }

    switch (sort) {
      case BillingSort.highestBill:
        list.sort((a, b) => b.totalBill.compareTo(a.totalBill));
      case BillingSort.lowestBill:
        list.sort((a, b) => a.totalBill.compareTo(b.totalBill));
      case BillingSort.mostMeals:
        list.sort((a, b) => b.presentCount.compareTo(a.presentCount));
      case BillingSort.leastMeals:
        list.sort((a, b) => a.presentCount.compareTo(b.presentCount));
      case BillingSort.name:
        list.sort((a, b) =>
            a.userName.toLowerCase().compareTo(b.userName.toLowerCase()));
      case BillingSort.newest:
        list.sort((a, b) => byDate(b.lastActivity, a.lastActivity));
      case BillingSort.oldest:
        list.sort((a, b) => byDate(a.lastActivity, b.lastActivity));
    }
    return list;
  }

  Future<void> init(UserModel user) async {
    _organizationId = user.organizationId;
    final res =
        await _groupRepo.getOrganisationGroups(organizationId: _organizationId);
    loadingGroups = false;
    if (res case Ok(:final value)) {
      groups = value.data;
      groupId = groups.isNotEmpty ? groups.first.id : null;
    }
    notifyListeners();
    if (groupId != null) await compute();
  }

  void selectGroup(String? id) {
    if (id == null || id == groupId) return;
    groupId = id;
    notifyListeners();
    compute();
  }

  void setPeriod(BillingPeriod p) {
    period = p;
    final now = DateTime.now();
    switch (p) {
      case BillingPeriod.today:
        from = DateTime(now.year, now.month, now.day);
        to = now;
      case BillingPeriod.week:
        from = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        to = now;
      case BillingPeriod.month:
        from = DateTime(now.year, now.month, 1);
        to = now;
      case BillingPeriod.custom:
        break;
    }
    notifyListeners();
    if (p != BillingPeriod.custom) compute();
  }

  void setCustomRange(DateTime f, DateTime t) {
    period = BillingPeriod.custom;
    from = f;
    to = t;
    notifyListeners();
    compute();
  }

  void setSort(BillingSort s) {
    sort = s;
    notifyListeners();
  }

  void setSearch(String q) {
    search = q;
    notifyListeners();
  }

  void setBucket(BillingBucket b) {
    if (b == bucket) return;
    bucket = b;
    notifyListeners();
    _loadSeries();
  }

  String get _bucketName => bucket == BillingBucket.month
      ? 'month'
      : bucket == BillingBucket.week
          ? 'week'
          : 'day';

  Future<void> _loadSeries() async {
    if (groupId == null) return;
    final res = await _attendanceRepo.getBillingSeries(
      organizationId: _organizationId,
      groupId: groupId!,
      from: from,
      to: to,
      bucket: _bucketName,
    );
    if (res case Ok(:final value)) {
      series = value;
      notifyListeners();
    }
  }

  Future<void> compute() async {
    if (groupId == null) return;
    loading = true;
    error = null;
    notifyListeners();

    final res = await _attendanceRepo.getBillingSummaryV2(
      organizationId: _organizationId,
      groupId: groupId!,
      from: from,
      to: to,
    );
    switch (res) {
      case Ok(:final value):
        summary = value;
      case Err(:final failure):
        error = failure.message;
        summary = BillingSummaryV2.empty;
    }
    await _loadSeries();
    loading = false;
    notifyListeners();
  }
}

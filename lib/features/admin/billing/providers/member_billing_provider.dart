import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/data/services/selected_group_store.dart';
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
        // Consistency fix: sort by the same NET figure the rows headline.
        list.sort((a, b) => b.netBill.compareTo(a.netBill));
      case BillingSort.lowestBill:
        list.sort((a, b) => a.netBill.compareTo(b.netBill));
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

    // Cache-first for the GROUP SELECTOR only: paint the dropdown instantly from
    // the shared org-groups cache (the same key admin Groups/Meals populate — so
    // this also de-duplicates that list across tabs). The financial numbers
    // below (getBillingSummaryV2 / series) are intentionally NEVER cached — they
    // are always fetched live so billing figures are never stale.
    // Miss-vs-empty aware: a cached EMPTY org (no groups yet) paints the real
    // empty state instantly; only a true cache MISS keeps the loader.
    final cachedGroups = await ResponseCacheService.instance.readListOrNull(
        _orgGroupsCacheKey, GroupModel.fromJson,
        maxAge: const Duration(hours: 12));
    if (cachedGroups != null && cachedGroups.isNotEmpty) {
      groups = cachedGroups;
      // ISSUE-003: follow the app-wide selected group (SelectedGroupStore),
      // falling back to the first group only when none is stored/valid.
      final savedId =
          await SelectedGroupStore.instance.read(_organizationId);
      groupId = groups
          .firstWhere((g) => g.id == savedId, orElse: () => groups.first)
          .id;
      loadingGroups = false;
      // Issue 3: a group is now selected and compute() will run — show the
      // loader, never the empty "No data for this range", until figures arrive.
      loading = true;
      notifyListeners();
      // Start the LIVE financial fetch NOW, in parallel with the groups
      // refresh below — the screen is fully fresh after one round-trip wave
      // instead of groups-then-figures sequentially.
      unawaited(compute());
    } else if (cachedGroups != null) {
      loadingGroups = false;
      notifyListeners();
    }
    final computedFor = groupId;

    final res =
        await _groupRepo.getOrganisationGroups(organizationId: _organizationId);
    loadingGroups = false;
    if (res case Ok(:final value)) {
      groups = value.data;
      if (groupId == null && groups.isNotEmpty) {
        // ISSUE-003: cold path (no cached groups) — same store-first rule.
        final savedId =
            await SelectedGroupStore.instance.read(_organizationId);
        groupId = groups
            .firstWhere((g) => g.id == savedId, orElse: () => groups.first)
            .id;
      }
      ResponseCacheService.instance
          .writeList(_orgGroupsCacheKey, value.data, (g) => g.toJson());
    }
    // Issue 3: if a group is selected, compute() is about to run — set loading
    // now so the frame between here and compute()'s own notify never paints the
    // empty "No data for this range" state.
    if (groupId != null && groupId != computedFor) loading = true;
    notifyListeners();
    // Only compute here when the cached path didn't already start it for the
    // SAME group (cold cache, or the refresh changed the selection).
    if (groupId != null && groupId != computedFor) await compute();
  }

  /// Shared org-groups cache key (same one admin Groups/Meals use), so the
  /// group selector is warm regardless of which admin tab was opened first.
  String get _orgGroupsCacheKey => 'admin_groups:$_organizationId';

  void selectGroup(String? id) {
    if (id == null || id == groupId) return;
    groupId = id;
    // ISSUE-003: an explicit switch here IS the app-wide selection now.
    unawaited(SelectedGroupStore.instance.write(_organizationId, id));
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

    // Summary + chart series are independent live reads — one parallel wave
    // (was sequential: figures RTT then series RTT).
    final resF = _attendanceRepo.getBillingSummaryV2(
      organizationId: _organizationId,
      groupId: groupId!,
      from: from,
      to: to,
    );
    final seriesF = _loadSeries();
    final res = await resF;
    switch (res) {
      case Ok(:final value):
        summary = value;
      case Err(:final failure):
        error = failure.message;
        summary = BillingSummaryV2.empty;
    }
    await seriesF;
    loading = false;
    notifyListeners();
  }
}

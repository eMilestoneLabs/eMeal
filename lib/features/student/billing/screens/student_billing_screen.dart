import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/billing_periods_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/my_billing.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Student Billing — a transparent, snapshot-accurate view of the student's OWN
/// meal charges. Fully additive: reuses [BillingService] (snapshot prices +
/// virtual auto-skip), the existing attendance/meal repositories scoped to the
/// signed-in student, and [ExportService] for PDF / XLSX / CSV. No backend or
/// contract change — historical prices come from each record's immutable
/// `price` snapshot, never live meal pricing.
class StudentBillingScreen extends StatefulWidget {
  const StudentBillingScreen({super.key});

  @override
  State<StudentBillingScreen> createState() => _StudentBillingScreenState();
}

enum _Period { today, week, month, custom }

enum _StatusFilter { all, present, skipped, autoSkipped, absent }

class _StudentBillingScreenState extends State<StudentBillingScreen> {
  final _attendanceRepo = AttendanceRepository();
  final _mealRepo = MealRepository();
  final _groupRepo = GroupRepository();
  final _billingRepo = BillingPeriodsRepository();

  bool _loading = true;
  bool _exporting = false;
  String? _error;

  _Period _period = _Period.month;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();

  _StatusFilter _statusFilter = _StatusFilter.all;
  String? _prefFilter; // null = all preferences

  // Data
  List<BillingRow> _rows = [];
  BillingSummary? _summary;
  // Issue 5: authoritative net (meal + guest + adjustments) from the same
  // backend engine as the admin dashboard, so both sides show one number.
  MyBilling? _serverBilling;
  // command_6 (survey 2026-07-13): admin-proposed debits awaiting MY approval
  // — they bill only after I approve (member-consent workflow).
  List<Map<String, dynamic>> _pendingCharges = [];
  bool _deciding = false;
  bool _pricingEnabled = false;
  // SRS Module 03 (survey Q17/Q22): group Bill-Skip policy.
  bool _billSkippedMeals = false;
  // Live-Test-7 ISSUE-4: independent Absent-billing policy (effective value).
  bool _billAbsentMeals = false;
  String _groupName = '';

  // Cached for export (same inputs the on-screen rows were built from).
  List<AttendanceModel> _records = [];
  List<MealModel> _meals = [];
  List<MealModel> _todayMeals = [];
  Set<String> _vacationUserIds = {};

  String _orgId = '';
  String _userId = '';
  String _groupId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'You must be signed in to view billing.';
      });
      return;
    }
    _orgId = user.organizationId;
    _userId = user.id;
    _groupId = user.groupId ??
        (user.effectiveGroupIds.isNotEmpty
            ? user.effectiveGroupIds.first
            : '');
    if (_groupId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Join a group to see your billing.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // ONE parallel wave (was 5 sequential round-trips — the whole screen
    // waited ~5× a single RTT). All five reads are independent; the my-billing
    // result is simply ignored below when the group turns out to be unpriced.
    final recF = _attendanceRepo.getAttendanceHistory(
      userId: _userId,
      groupId: _groupId,
      organizationId: _orgId,
      from: _from,
      to: _to,
      params: const PaginationParams(page: 1, limit: 100),
    );
    final mealF = _mealRepo.getGroupMeals(
      organizationId: _orgId,
      groupId: _groupId,
    );
    final todayF = _mealRepo.getTodayMeals(
      organizationId: _orgId,
      groupId: _groupId,
    );
    final groupF = _groupRepo.getGroup(
      organizationId: _orgId,
      groupId: _groupId,
    );
    final mbF = _attendanceRepo.getMyBilling(
      groupId: _groupId,
      from: _from,
      to: _to,
    );
    // Rides the same parallel wave — pending debit approvals (self-scoped).
    final pendF = _billingRepo.myPendingAdjustments();
    final recRes = await recF;
    final mealRes = await mealF;
    final todayRes = await todayF;
    final groupRes = await groupF;
    if (!mounted) return;

    List<AttendanceModel> records = [];
    if (recRes case Ok(:final value)) {
      records = value.data;
    } else if (recRes case Err(:final failure)) {
      _error = failure.message;
    }
    List<MealModel> meals = [];
    if (mealRes case Ok(:final value)) meals = value;
    List<MealModel> todayMeals = [];
    if (todayRes case Ok(:final value)) todayMeals = value;
    if (groupRes case Ok(:final value)) {
      _pricingEnabled = value.mealConfig.mealPricingEnabled;
      _billSkippedMeals = value.mealConfig.billSkippedMeals;
      _billAbsentMeals = value.mealConfig.billAbsentMeals;
      _groupName = value.name;
    }

    final vacationIds = <String>{};
    if (user.isVacationMode) vacationIds.add(_userId);

    final rows = BillingService.buildRows(
      records: records,
      meals: meals,
      from: _from,
      to: _to,
      todayMeals: todayMeals,
      vacationUserIds: vacationIds,
    ).where((r) => r.userId == _userId).toList();
    final summaries = BillingService.summarize(rows,
        billSkippedMeals: _billSkippedMeals, billAbsentMeals: _billAbsentMeals);

    // Issue 5: pull the authoritative net from the shared billing engine. This
    // is the ONLY number that includes hosted-guest charges + admin
    // credits/refunds, so it reconciles exactly with what the admin bills.
    // Best-effort: if it fails, the screen still shows the client-side meal
    // subtotal rather than breaking (the per-day history is unaffected).
    MyBilling? serverBilling;
    if (_pricingEnabled) {
      // Already in flight since the parallel wave above — no extra wait here.
      final mbRes = await mbF;
      if (!mounted) return;
      if (mbRes case Ok(:final value)) serverBilling = value;
    } else {
      // Unpriced group: silence the unused in-flight future (Result API —
      // never throws), preserving the old "only fetched when priced" shape.
      unawaited(mbF.then((_) {}));
    }

    var pending = <Map<String, dynamic>>[];
    final pendRes = await pendF;
    if (!mounted) return;
    if (pendRes case Ok(:final value)) {
      pending = value
          .where((e) => (e['groupId'] ?? '').toString() == _groupId)
          .toList();
    }

    setState(() {
      _records = records;
      _meals = meals;
      _todayMeals = todayMeals;
      _vacationUserIds = vacationIds;
      _rows = rows;
      _summary = summaries.isNotEmpty ? summaries.first : null;
      _serverBilling = serverBilling;
      _pendingCharges = pending;
      _loading = false;
    });
  }

  void _applyPeriod(_Period p) {
    final now = DateTime.now();
    setState(() {
      _period = p;
      switch (p) {
        case _Period.today:
          _from = DateTime(now.year, now.month, now.day);
          _to = now;
        case _Period.week:
          _from = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _to = now;
        case _Period.month:
          _from = DateTime(now.year, now.month, 1);
          _to = now;
        case _Period.custom:
          break;
      }
    });
    if (p != _Period.custom) _load();
  }

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked != null) {
      setState(() {
        _period = _Period.custom;
        _from = picked.start;
        _to = picked.end;
      });
      _load();
    }
  }

  /// The signed-in member's own guest + adjustment figures (from the shared
  /// billing engine) so the exported summary carries the SAME net bill the
  /// screen shows — hosted guests billed to this member, itemised.
  Map<String, MemberExportFinancials> get _exportFinancials {
    final uid = AuthProviderScope.of(context).currentUser?.id;
    final sb = _serverBilling;
    if (uid == null || sb == null) return const {};
    return {
      uid: MemberExportFinancials(
        guestCount: sb.guestCount,
        guestAmount: sb.guestAmount,
        adjustmentsTotal: sb.adjustmentsTotal,
        openingBalance: sb.openingBalance,
      ),
    };
  }

  Future<void> _export(String fmt) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final svc = ExportService.instance;
    final label = '${_fmtDate(_from)} - ${_fmtDate(_to)}';
    final name = _groupName.isEmpty ? 'My Billing' : _groupName;
    final financials = _exportFinancials;
    try {
      switch (fmt) {
        case 'pdf':
          await svc.exportPdf(
            records: _records,
            meals: _meals,
            groupName: name,
            pricingEnabled: _pricingEnabled,
            from: _from,
            to: _to,
            dateRangeLabel: label,
            todayMeals: _todayMeals,
            vacationUserIds: _vacationUserIds,
            financialsByUser: financials,
            billSkippedMeals: _billSkippedMeals,
            billAbsentMeals: _billAbsentMeals,
          );
        // RPT-001: CSV export removed — Excel + PDF only.
        default:
          await svc.exportXlsx(
            records: _records,
            meals: _meals,
            groupName: name,
            pricingEnabled: _pricingEnabled,
            from: _from,
            to: _to,
            dateRangeLabel: label,
            todayMeals: _todayMeals,
            vacationUserIds: _vacationUserIds,
            financialsByUser: financials,
            billSkippedMeals: _billSkippedMeals,
            billAbsentMeals: _billAbsentMeals,
          );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export ready - share sheet opened.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── Derived ────────────────────────────────────────────────────────────────

  List<String> get _preferenceOptions {
    final set = <String>{};
    for (final r in _rows) {
      final p = r.preference;
      if (p != null && p.trim().isNotEmpty) set.add(p);
    }
    final list = set.toList()..sort();
    return list;
  }

  bool _matchesStatus(BillingRow r) {
    switch (_statusFilter) {
      case _StatusFilter.all:
        return true;
      case _StatusFilter.present:
        return r.status == AttendanceStatus.present;
      case _StatusFilter.skipped:
        return r.status == AttendanceStatus.skipped && !r.autoSkipped;
      case _StatusFilter.autoSkipped:
        return r.status == AttendanceStatus.skipped && r.autoSkipped;
      case _StatusFilter.absent:
        return r.status == AttendanceStatus.absent;
    }
  }

  List<BillingRow> get _filteredRows {
    return _rows.where((r) {
      if (!_matchesStatus(r)) return false;
      if (_prefFilter != null && r.preference != _prefFilter) return false;
      return true;
    }).toList();
  }

  /// Rows grouped by yyyy-mm-dd, newest day first.
  List<MapEntry<DateTime, List<BillingRow>>> get _byDate {
    final map = <String, List<BillingRow>>{};
    final keyDate = <String, DateTime>{};
    for (final r in _filteredRows) {
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      final k = _fmtDate(d);
      map.putIfAbsent(k, () => []).add(r);
      keyDate[k] = d;
    }
    final entries = map.entries
        .map((e) => MapEntry(keyDate[e.key]!, e.value))
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }

  Map<String, int> get _mealWiseTotals {
    // Live-Test-5 ISSUE-4: per-meal detail includes policy-billed skipped or
    // absent rows (Bill-Skip ON) so the split reconciles with the server's
    // Meal-Charges component instead of silently omitting billed meals.
    final out = <String, int>{};
    for (final r in _rows) {
      final billed = _rowBilledAmount(r);
      if (billed > 0) {
        out[r.mealName] = (out[r.mealName] ?? 0) + billed;
      }
    }
    return out;
  }

  BillingRow? get _lastCharged {
    BillingRow? best;
    for (final r in _rows) {
      if (r.status != AttendanceStatus.present) continue;
      final t = r.markedAt ?? r.date;
      final bt = best?.markedAt ?? best?.date;
      if (best == null || (bt != null && t.isAfter(bt))) best = r;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: const Text('My Billing'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else if (_pricingEnabled)
            PopupMenuButton<String>(
              tooltip: 'Export',
              icon: const Icon(Icons.ios_share_rounded, size: 20),
              onSelected: _export,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                PopupMenuItem(value: 'xlsx', child: Text('Export Excel')),
                // RPT-001: CSV export removed — Excel + PDF only.
              ],
            ),
        ],
      ),
      body: _loading
          ? const AppDetailSkeleton(headerHeight: 150, rows: 5, rowHeight: 68)
          : _error != null
              ? _infoCard(isDark, _error!, AppColors.error)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _periodSelector(isDark),
                      const SizedBox(height: 8),
                      Text('${_fmtDate(_from)} - ${_fmtDate(_to)}',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textTertiary)),
                      const SizedBox(height: 14),
                      if (_pendingCharges.isNotEmpty) ...[
                        _pendingChargesCard(isDark),
                        const SizedBox(height: 16),
                      ],
                      _summarySection(isDark),
                      const SizedBox(height: 16),
                      _currentStatusCard(isDark),
                      const SizedBox(height: 16),
                      _filtersRow(isDark),
                      const SizedBox(height: 14),
                      _historySection(isDark),
                      const SizedBox(height: 18),
                      if (_pricingEnabled) _financialBreakdown(isDark),
                    ],
                  ),
                ),
    );
  }

  // ── Sections ─────────────────────────────────────────────────────────────

  Widget _summarySection(bool isDark) {
    final s = _summary;
    final sb = _serverBilling;
    final present = s?.present ?? 0;
    // Authoritative net (meal + guest + adjustments) when available; the
    // client meal subtotal is the graceful fallback. Avg-per-meal always uses
    // meal charges (guests/adjustments aren't per own-meal).
    final bill = sb?.netBill ?? s?.totalBill ?? 0;
    final mealCharges = sb?.mealCharges ?? s?.totalBill ?? 0;
    final avg = present > 0 ? (mealCharges / present).round() : 0;
    String mostConsumed = '-';
    if (s != null && s.consumedByMeal.isNotEmpty) {
      mostConsumed = s.consumedByMeal.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
    }
    final cards = <Widget>[
      if (_pricingEnabled)
        _statCard(isDark, 'Total Bill', _cur(bill),
            Icons.account_balance_wallet_rounded, AppColors.primary),
      _statCard(isDark, 'Present', '$present', Icons.restaurant_rounded,
          AppColors.present),
      // Includes virtual auto-skips (closed windows never marked) — matches
      // the admin's member detail; the admin LIST counts only marked skips.
      _statCard(isDark, 'Skipped (incl. auto)', '${s?.skipped ?? 0}',
          Icons.skip_next_rounded, AppColors.warning),
      _statCard(isDark, 'Absent', '${s?.absent ?? 0}',
          Icons.event_busy_rounded, AppColors.absent),
      if (_pricingEnabled)
        _statCard(isDark, 'Avg Meal', _cur(avg), Icons.trending_up_rounded,
            AppColors.info),
      _statCard(isDark, 'Top Meal', mostConsumed, Icons.star_rounded,
          AppColors.secondary),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth < 560;
        if (!twoCol) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final w in cards)
                SizedBox(width: (c.maxWidth - 12 * 2) / 3, child: w),
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final w in cards)
              SizedBox(width: (c.maxWidth - 12) / 2, child: w),
          ],
        );
      },
    );
  }

  Widget _statCard(
      bool isDark, String label, String value, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: 8),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium
                  .copyWith(fontWeight: FontWeight.w800)),
          Text(label,
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _currentStatusCard(bool isDark) {
    final last = _lastCharged;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Current Bill',
              style: AppTypography.labelMedium
                  .copyWith(color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          Text(
              _pricingEnabled
                  ? _cur(_serverBilling?.netBill ?? _summary?.totalBill ?? 0)
                  : 'No charges',
              style: AppTypography.headlineSmall.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          if (last != null)
            Text(
              'Last charged: ${last.mealName} - ${_fmtDate(last.date)}'
              '${_pricingEnabled ? '  ${_cur(last.price ?? 0)}' : ''}',
              style: AppTypography.bodySmall
                  .copyWith(color: Colors.white.withValues(alpha: 0.9)),
            )
          else
            Text('No charged meals in this period.',
                style: AppTypography.bodySmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.9))),
        ],
      ),
    );
  }

  Widget _filtersRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _dropdownShell(
            isDark,
            DropdownButton<_StatusFilter>(
              isExpanded: true,
              value: _statusFilter,
              underline: const SizedBox.shrink(),
              style: AppTypography.labelMedium
                  .copyWith(color: isDark ? Colors.white : Colors.black87),
              items: const [
                DropdownMenuItem(
                    value: _StatusFilter.all, child: Text('All status')),
                DropdownMenuItem(
                    value: _StatusFilter.present, child: Text('Present')),
                DropdownMenuItem(
                    value: _StatusFilter.skipped, child: Text('Skipped')),
                DropdownMenuItem(
                    value: _StatusFilter.autoSkipped,
                    child: Text('Auto skipped')),
                DropdownMenuItem(
                    value: _StatusFilter.absent, child: Text('Absent')),
              ],
              onChanged: (v) =>
                  setState(() => _statusFilter = v ?? _StatusFilter.all),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _dropdownShell(
            isDark,
            DropdownButton<String?>(
              isExpanded: true,
              value: _prefFilter,
              underline: const SizedBox.shrink(),
              hint: Text('All prefs',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.textTertiary)),
              style: AppTypography.labelMedium
                  .copyWith(color: isDark ? Colors.white : Colors.black87),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All prefs')),
                ..._preferenceOptions.map((p) => DropdownMenuItem<String?>(
                      value: p,
                      child: Text(_cap(p)),
                    )),
              ],
              onChanged: (v) => setState(() => _prefFilter = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownShell(bool isDark, Widget child) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.6)),
      ),
      child: DropdownButtonHideUnderline(child: child),
    );
  }

  Widget _historySection(bool isDark) {
    final groups = _byDate;
    if (groups.isEmpty) {
      return _infoCard(isDark, 'No meal records for this range.',
          AppColors.primary);
    }
    return Column(
      children: [
        for (final g in groups) ...[
          _dateGroupCard(isDark, g.key, g.value),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _dateGroupCard(bool isDark, DateTime date, List<BillingRow> rows) {
    final ordered = [...rows];
    int subtotal = 0;
    for (final r in rows) {
      subtotal += _rowBilledAmount(r);
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(_fmtDateLong(date),
                      style: AppTypography.labelLarge
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
                if (_pricingEnabled)
                  Text(_cur(subtotal),
                      style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final r in ordered) _mealRow(isDark, r),
        ],
      ),
    );
  }

  /// Live-Test-5 ISSUE-4 (enterprise display rules 1–4): the amount a row
  /// actually contributes to the bill. Present = charged price; skipped or
  /// absent = charged price ONLY when the group's Bill-Skip policy is ON;
  /// everything else contributes ₹0.
  int _rowBilledAmount(BillingRow r) {
    if (r.status == AttendanceStatus.present) return r.price ?? 0;
    final billSkips = _billSkippedMeals || (_serverBilling?.billSkippedMeals ?? false);
    // Live-Test-7 ISSUE-4: Absent follows its own independent policy.
    final billAbsents = _billAbsentMeals || (_serverBilling?.billAbsentMeals ?? false);
    // Live-Test-6 ISSUE-4: only REAL records are ever billed — the engine
    // bills its own system-generated Skip records, never the client's virtual
    // placeholder rows (autoSkipped). Labelling placeholders "Billed" showed
    // phantom charges the engine never applied.
    if (!r.autoSkipped &&
        ((r.status == AttendanceStatus.skipped && billSkips) ||
            (r.status == AttendanceStatus.absent && billAbsents))) {
      return r.price ?? 0;
    }
    return 0;
  }

  Widget _mealRow(bool isDark, BillingRow r) {
    final statusColor = _statusColor(r);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.mealName,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 2,
                  children: [
                    Text(_statusLabel(r),
                        style: AppTypography.labelSmall.copyWith(
                            color: statusColor, fontWeight: FontWeight.w700)),
                    if (r.preference != null && r.preference!.isNotEmpty)
                      Text('• ${_cap(r.preference!)}',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textTertiary)),
                    if (r.markedAt != null)
                      Text('• ${_fmtTime(r.markedAt!)}',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ],
            ),
          ),
          if (_pricingEnabled)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _cur(_rowBilledAmount(r)),
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _rowBilledAmount(r) > 0
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                  ),
                ),
                // Rules 2/3: a non-Present row states WHY it is (not) billed
                // so the policy is understandable from the screen itself.
                if (r.status == AttendanceStatus.skipped ||
                    r.status == AttendanceStatus.absent)
                  Text(
                    _rowBilledAmount(r) > 0 ? 'Billed' : 'Not billed',
                    style: AppTypography.labelSmall.copyWith(
                      color: _rowBilledAmount(r) > 0
                          ? AppColors.warning
                          : AppColors.textTertiary,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _financialBreakdown(bool isDark) {
    final totals = _mealWiseTotals;
    final grand = totals.values.fold<int>(0, (a, b) => a + b);
    final sb = _serverBilling;
    final net = sb?.netBill ?? grand;
    // Live-Test-5 ISSUE-4: the summary lines come from the SERVER components
    // (meal charges include policy-billed skipped/absent meals), so the lines
    // always sum exactly to Net Payable. The client-side per-meal split stays
    // as detail rows under the server Meal-Charges line.
    final mealCharges = sb?.mealCharges ?? grand;
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Financial breakdown',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          // CREDIT-001: carried-forward opening balance — display row only,
          // its value is already included in the Net Total below.
          if (sb != null && sb.openingBalance != 0)
            _breakdownRow(
              sb.openingBalance > 0
                  ? 'Opening balance (dues carried forward)'
                  : 'Opening balance (credit carried forward)',
              '${sb.openingBalance > 0 ? '+' : '−'}${_cur(sb.openingBalance.abs())}',
              sb.openingBalance > 0 ? AppColors.warning : AppColors.present,
            ),
          if (entries.isEmpty && mealCharges == 0)
            Text('No charges yet.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textTertiary))
          else ...[
            // Enterprise policy: Meal Charges is ONE independent component
            // (server figure — includes policy-billed skipped/absent meals).
            _breakdownRow('Meal charges', _cur(mealCharges), null),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                          child: Text(e.key,
                              style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.textTertiary))),
                      Text(_cur(e.value),
                          style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
          ],
          // Each financial concept is its OWN line — never merged (policy).
          if (sb != null && sb.guestAmount != 0)
            _breakdownRow('Guest charges (${sb.guestCount})',
                _cur(sb.guestAmount), AppColors.secondary),
          if (sb != null && sb.debitsTotal != 0)
            _breakdownRow('Debits (approved charges)',
                '+${_cur(sb.debitsTotal)}', AppColors.warning),
          if (sb != null && sb.creditsTotal != 0)
            _breakdownRow('Credits', '−${_cur(sb.creditsTotal)}',
                AppColors.present),
          if (sb != null && sb.refundsTotal != 0)
            // REF-001: a refund = cash physically returned to the member —
            // it consumes available credit, so Net Payable moves toward zero.
            _breakdownRow('Refunds (cash returned)',
                '+${_cur(sb.refundsTotal)}', AppColors.warning),
          // Legacy fallback: server rows without the itemised fields still
          // reconcile through the single signed adjustments line.
          if (sb != null &&
              sb.adjustmentsTotal != 0 &&
              sb.debitsTotal == 0 &&
              sb.creditsTotal == 0 &&
              sb.refundsTotal == 0)
            _breakdownRow(
              sb.adjustmentsTotal > 0
                  ? 'Adjustments (charges)'
                  : 'Adjustments (credits / refunds)',
              '${sb.adjustmentsTotal > 0 ? '+' : '−'}${_cur(sb.adjustmentsTotal.abs())}',
              sb.adjustmentsTotal > 0 ? AppColors.warning : AppColors.present,
            ),
          const Divider(height: 22),
          Row(
            children: [
              Expanded(
                child: Text('Net Payable',
                    style: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(_cur(net),
                  style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  // ── command_6 (survey 2026-07-13): member-consent debit approvals ────────

  Widget _pendingChargesCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pending_actions_rounded,
                  color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Charges awaiting your approval',
                    style: AppTypography.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('A proposed charge bills you only after you approve it.',
              style: AppTypography.labelSmall
                  .copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 10),
          for (final e in _pendingCharges) _pendingChargeTile(isDark, e),
        ],
      ),
    );
  }

  Widget _pendingChargeTile(bool isDark, Map<String, dynamic> e) {
    final amountPaise = (e['amount'] as num?) ?? 0;
    final reason = (e['reason'] ?? '').toString();
    final date = (e['entryDate'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(reason.isEmpty ? 'Proposed charge' : reason,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
              Text('+${_cur((amountPaise / 100).round())}',
                  style: AppTypography.titleSmall.copyWith(
                      color: AppColors.warning, fontWeight: FontWeight.w800)),
            ],
          ),
          if (date.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(date,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _deciding ? null : () => _decideCharge(e, approve: false),
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: const Text('Decline'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.5)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _deciding ? null : () => _decideCharge(e, approve: true),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('Approve'),
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.present),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _decideCharge(Map<String, dynamic> e,
      {required bool approve}) async {
    if (_deciding) return;
    setState(() => _deciding = true);
    final res = await _billingRepo.decideAdjustment(
      entryId: (e['id'] ?? '').toString(),
      approve: approve,
    );
    if (!mounted) return;
    setState(() => _deciding = false);
    switch (res) {
      case Ok():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor:
                approve ? AppColors.present : AppColors.textSecondary,
            content: Text(approve
                ? 'Charge approved — added to your bill'
                : 'Charge declined'),
          ),
        );
        _load();
      case Err(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
            content: Text(failure.message),
          ),
        );
    }
  }

  Widget _periodSelector(bool isDark) {
    Widget seg(String label, _Period p) {
      final sel = _period == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => p == _Period.custom ? _pickCustom() : _applyPeriod(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : AppColors.textSecondary,
                )),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: (isDark ? AppColors.borderDark : AppColors.border)
                .withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          seg('Today', _Period.today),
          seg('Week', _Period.week),
          seg('Month', _Period.month),
          seg('Custom', _Period.custom),
        ],
      ),
    );
  }

  Widget _infoCard(bool isDark, String message, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(message,
          style: AppTypography.bodySmall.copyWith(color: color)),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  // Negative-safe (credits can exceed the bill): -₹962, not ₹-962.
  String _cur(int v) => v < 0 ? '-₹${-v}' : '₹$v';

  Widget _breakdownRow(String label, String value, Color? color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.bodySmall)),
            Text(value,
                style: AppTypography.bodySmall
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _statusLabel(BillingRow r) {
    switch (r.status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.skipped:
        return r.autoSkipped ? 'Skipped (auto)' : 'Skipped';
      default:
        return '-';
    }
  }

  Color _statusColor(BillingRow r) {
    switch (r.status) {
      case AttendanceStatus.present:
        return AppColors.present;
      case AttendanceStatus.absent:
        return AppColors.absent;
      case AttendanceStatus.skipped:
        return AppColors.warning;
      default:
        return AppColors.textTertiary;
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _fmtDateLong(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}

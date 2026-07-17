import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Member Billing Detail (V2) — dedicated screen (not a bottom sheet).
class MemberBillingDetailScreen extends StatefulWidget {
  const MemberBillingDetailScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.role,
    required this.groupId,
    required this.organizationId,
    required this.groupName,
    required this.from,
    required this.to,
    required this.pricingEnabled,
    this.billSkippedMeals = false,
    this.guestCount = 0,
    this.guestAmount = 0,
    this.adjustmentsTotal = 0,
    this.debitsTotal = 0,
    this.creditsTotal = 0,
    this.refundsTotal = 0,
    this.openingBalance = 0,
    this.engineMealCharges,
    this.engineNetBill,
  });

  final String userId;
  final String userName;
  final String role;
  final String groupId;
  final String organizationId;
  final String groupName;
  final DateTime from;
  final DateTime to;
  final bool pricingEnabled;

  /// SRS Module 03 (survey Q17/Q22): group Bill-Skip policy — bills
  /// Absent/Skipped rows at their scheduled price when true.
  final bool billSkippedMeals;

  /// Billing-consistency fix: the same hosted-guest charges and signed ledger
  /// adjustments the Member Billing list shows, so this screen's headline is
  /// the SAME net figure the member sees on their own My Billing screen
  /// (net = meals + guests + adjustments) instead of a meals-only number.
  final int guestCount;
  final int guestAmount;
  final int adjustmentsTotal;

  /// Live-Test-5 ISSUE-4 (enterprise display policy): itemised ledger
  /// components — Debits / Credits / Refunds are separate business concepts
  /// and render as separate lines (positive magnitudes; display applies the
  /// REF-001 signs: debit +, credit −, refund + as credit-returned-as-cash).
  final int debitsTotal;
  final int creditsTotal;
  final int refundsTotal;

  /// CREDIT-001 (2026-07-13): balance carried forward from the previous
  /// finalized billing period — included in the net headline, itemised below.
  final int openingBalance;

  /// Live-Test-6 ISSUE-4 (billing display parity): the billing ENGINE's own
  /// figures for this member (mealCharges = own meals incl. policy-billed
  /// skips; netBill = the full net), passed straight from the Member Billing
  /// list row. When present they are the headline source of truth — the
  /// screen never re-derives money the engine already computed.
  final int? engineMealCharges;
  final int? engineNetBill;

  @override
  State<MemberBillingDetailScreen> createState() =>
      _MemberBillingDetailScreenState();
}

class _MemberBillingDetailScreenState extends State<MemberBillingDetailScreen> {
  final _attendanceRepo = AttendanceRepository();
  final _mealRepo = MealRepository();
  final _groupRepo = GroupRepository();

  bool _loading = true;
  String? _error;
  List<BillingRow> _rows = [];
  BillingSummary? _summary;
  Map<String, MealModel> _mealById = {};
  List<AttendanceModel> _records = [];
  List<MealModel> _meals = [];
  // Issue 3 & 7: cached so exports reuse the same per-day overlay + vacation set
  // as the on-screen billing rows.
  List<MealModel> _todayMeals = [];
  Set<String> _vacationUserIds = {};
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // ONE parallel wave (was 4 sequential round-trips): all four reads are
    // independent — start them together, then await in order.
    final recF = _attendanceRepo.getAttendanceHistory(
      userId: widget.userId,
      groupId: widget.groupId,
      organizationId: widget.organizationId,
      from: widget.from,
      to: widget.to,
      params: const PaginationParams(page: 1, limit: 100),
    );
    final mealF = _mealRepo.getGroupMeals(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );
    // Issue 3: today's effective (published per-day) windows/prices so the
    // virtual auto-skip never fires while today's real window is still open.
    final todayF = _mealRepo.getTodayMeals(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );
    // Issue 7: members currently in Vacation Mode are excluded from attendance
    // calculations — never synthesise a virtual auto-skip for them.
    final membersF = _groupRepo.getGroupMembers(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );
    final recRes = await recF;
    final mealRes = await mealF;
    final todayRes = await todayF;
    final membersRes = await membersF;

    List<AttendanceModel> records = [];
    String? err;
    if (recRes case Ok(:final value)) {
      records = value.data;
    } else if (recRes case Err(:final failure)) {
      err = failure.message;
    }
    List<MealModel> meals = [];
    if (mealRes case Ok(:final value)) meals = value;
    List<MealModel> todayMeals = [];
    if (todayRes case Ok(:final value)) todayMeals = value;
    final vacationUserIds = <String>{};
    if (membersRes case Ok(:final value)) {
      for (final m in value.data) {
        if (m.isVacationMode) vacationUserIds.add(m.id);
      }
    }

    final rows = BillingService.buildRows(
      records: records,
      meals: meals,
      from: widget.from,
      to: widget.to,
      todayMeals: todayMeals,
      vacationUserIds: vacationUserIds,
    ).where((r) => r.userId == widget.userId).toList();
    final summaries = BillingService.summarize(rows,
        billSkippedMeals: widget.billSkippedMeals);

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _summary = summaries.isNotEmpty ? summaries.first : null;
      _mealById = {for (final m in meals) m.id: m};
      _records = records;
      _meals = meals;
      _todayMeals = todayMeals;
      _vacationUserIds = vacationUserIds;
      _loading = false;
      _error = err;
    });
  }

  /// Guest + adjustment figures for this member so the exported summary is
  /// the SAME net bill the screen (and the member's My Billing) shows.
  Map<String, MemberExportFinancials> get _exportFinancials => {
        widget.userId: MemberExportFinancials(
          guestCount: widget.guestCount,
          guestAmount: widget.guestAmount,
          adjustmentsTotal: widget.adjustmentsTotal,
          openingBalance: widget.openingBalance,
        ),
      };

  Future<void> _export(String fmt) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final svc = ExportService.instance;
    final label = '${_fmtDate(widget.from)} – ${_fmtDate(widget.to)}';
    final name = '${widget.userName} · ${widget.groupName}';
    try {
      switch (fmt) {
        case 'pdf':
          await svc.exportPdf(
            records: _records,
            meals: _meals,
            groupName: name,
            pricingEnabled: widget.pricingEnabled,
            from: widget.from,
            to: widget.to,
            dateRangeLabel: label,
            todayMeals: _todayMeals,
            vacationUserIds: _vacationUserIds,
            financialsByUser: _exportFinancials,
            billSkippedMeals: widget.billSkippedMeals,
          );
        // RPT-001: CSV export removed — Excel + PDF only.
        default:
          await svc.exportXlsx(
            records: _records,
            meals: _meals,
            groupName: name,
            pricingEnabled: widget.pricingEnabled,
            from: widget.from,
            to: widget.to,
            dateRangeLabel: label,
            todayMeals: _todayMeals,
            vacationUserIds: _vacationUserIds,
            financialsByUser: _exportFinancials,
            billSkippedMeals: widget.billSkippedMeals,
          );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export ready — share sheet opened.')),
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

  Map<DateTime, List<BillingRow>> get _byDate {
    final map = <DateTime, List<BillingRow>>{};
    for (final r in _rows) {
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      map.putIfAbsent(d, () => []).add(r);
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
  }

  Map<String, int> get _mealBreakdown {
    final map = <String, int>{};
    for (final r in _rows) {
      if (r.isPresent) {
        map[r.mealName] = (map[r.mealName] ?? 0) + (r.price ?? 0);
      }
    }
    return map;
  }

  String get _mostConsumedMeal {
    final counts = <String, int>{};
    for (final r in _rows) {
      if (r.isPresent) counts[r.mealName] = (counts[r.mealName] ?? 0) + 1;
    }
    if (counts.isEmpty) return '—';
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  int get _avgDailyCost {
    final days =
        _byDate.entries.where((e) => e.value.any((r) => r.isPresent)).length;
    // ISSUE-4: derived from the engine's own-meal charges, never the client
    // grid re-computation.
    final bill = _mealsBill;
    return days == 0 ? 0 : (bill / days).round();
  }

  /// Own-meal charges. Live-Test-6 ISSUE-4: the billing ENGINE's figure wins
  /// whenever the list passed it — the client grid (with its virtual
  /// placeholder rows) is display-only and must never set the money headline.
  int get _mealsBill =>
      widget.engineMealCharges ?? _summary?.totalBill ?? 0;

  /// The net bill. Engine figure verbatim when available; the local sum is
  /// only a fallback for legacy callers that didn't pass it.
  int get _netBill =>
      widget.engineNetBill ??
      (widget.openingBalance +
          _mealsBill +
          widget.guestAmount +
          widget.adjustmentsTotal);

  bool get _hasFinancialExtras =>
      widget.guestAmount != 0 ||
      widget.adjustmentsTotal != 0 ||
      widget.openingBalance != 0;

  static String _rupees(int v) => v < 0 ? '-₹${-v}' : '₹$v';

  String _fmtDate(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  String _fmtTime(DateTime? d) => d == null
      ? '—'
      : TimeFormat.tod12(TimeOfDay.fromDateTime(d));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(widget.userName, style: AppTypography.titleLarge),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          _exporting
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : PopupMenuButton<String>(
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Export',
                  onSelected: _export,
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                    PopupMenuItem(
                        value: 'xlsx', child: Text('Export Excel (.xlsx)')),
                    // RPT-001: CSV export removed — Excel + PDF only.
                  ],
                ),
        ],
      ),
      body: _loading
          ? const AppDetailSkeleton(headerHeight: 150, rows: 5)
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _header(cs),
                  const SizedBox(height: 16),
                  _statsGrid(cs),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Text(_error!,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.error)),
                    const SizedBox(height: 12),
                  ],
                  _sectionTitle('Meals by date'),
                  const SizedBox(height: 10),
                  ..._byDate.entries.map((e) => _dateGroup(cs, e.key, e.value)),
                  if (widget.pricingEnabled) ...[
                    const SizedBox(height: 12),
                    _sectionTitle('Financial breakdown'),
                    const SizedBox(height: 10),
                    _breakdownCard(cs),
                  ],
                  const SizedBox(height: 20),
                  _sectionTitle('Billing timeline'),
                  const SizedBox(height: 10),
                  ..._rows
                      .where((r) => r.isPresent)
                      .map((r) => _timelineTile(cs, r)),
                ],
              ),
            ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.userName,
              style: AppTypography.titleLarge
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${widget.role}  ·  ${widget.groupName}',
              style: AppTypography.bodySmall
                  .copyWith(color: Colors.white.withValues(alpha: 0.85))),
          Text('${_fmtDate(widget.from)} – ${_fmtDate(widget.to)}',
              style: AppTypography.labelSmall
                  .copyWith(color: Colors.white.withValues(alpha: 0.75))),
          if (widget.pricingEnabled) ...[
            const SizedBox(height: 14),
            Text(_hasFinancialExtras ? 'Net Bill' : 'Total Bill',
                style: AppTypography.labelSmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.85))),
            Text(_rupees(_netBill),
                style: AppTypography.numericMedium.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800)),
            // The same components the member list + student screen show, so
            // every surface tells one identical money story.
            if (_hasFinancialExtras)
              Text(
                'Meals ${_rupees(_mealsBill)}'
                '${widget.guestAmount != 0 ? ' · Guests +₹${widget.guestAmount}' : ''}'
                '${widget.adjustmentsTotal != 0 ? ' · Adjustments ${widget.adjustmentsTotal > 0 ? '+' : '−'}₹${widget.adjustmentsTotal.abs()}' : ''}',
                style: AppTypography.labelSmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.85)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statsGrid(ColorScheme cs) {
    final s = _summary;
    final items = <List<String>>[
      ['Present', '${s?.present ?? 0}'],
      // Includes virtual auto-skips (closed windows never marked) — the member
      // list's "Skipped" counts only explicitly marked skips, hence differs.
      ['Skipped (incl. auto)', '${s?.skipped ?? 0}'],
      ['Absent', '${s?.absent ?? 0}'],
      ['Total meals', '${s?.totalMeals ?? 0}'],
      if (widget.pricingEnabled) ['Avg daily', '₹$_avgDailyCost'],
      ['Top meal', _mostConsumedMeal],
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final it in items)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 32 - 20) / 3,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it[1],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleSmall
                          .copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(it[0],
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w700));

  /// Live-Test-6 ISSUE-4: a REAL skipped/absent record billed by the group's
  /// Bill-Skip policy — virtual placeholder rows (autoSkipped) are never
  /// billed, matching the billing engine exactly.
  bool _isPolicyBilled(BillingRow r) =>
      widget.billSkippedMeals &&
      !r.autoSkipped &&
      (r.status == AttendanceStatus.skipped ||
          r.status == AttendanceStatus.absent);

  Widget _dateGroup(ColorScheme cs, DateTime date, List<BillingRow> rows) {
    final subtotal = rows
        .where((r) => r.isPresent || _isPolicyBilled(r))
        .fold<int>(0, (s, r) => s + (r.price ?? 0));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Row(
              children: [
                Text(_fmtDate(date),
                    style: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (widget.pricingEnabled)
                  Text('₹$subtotal',
                      style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...rows.map((r) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.mealName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall
                              .copyWith(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    // Fixed-width status column so every row lines up vertically.
                    SizedBox(
                      width: 92,
                      child: Text(_statusText(r),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _statusColor(r))),
                    ),
                    // Fixed-width right-aligned price column. ISSUE-4: real
                    // policy-billed Skip/Absent rows show their charge so the
                    // on-screen math adds up; unbilled rows show '—'.
                    if (widget.pricingEnabled)
                      SizedBox(
                        width: 64,
                        child: Text(
                            r.isPresent || _isPolicyBilled(r)
                                ? '₹${r.price ?? 0}'
                                : '—',
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            style: AppTypography.labelSmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: r.isPresent || _isPolicyBilled(r)
                                    ? AppColors.textPrimary
                                    : AppColors.textTertiary)),
                      ),
                  ],
                ),
              )),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _breakdownCard(ColorScheme cs) {
    final b = _mealBreakdown;
    // ISSUE-4: the engine's own-meal charges minus the visible Present lines =
    // the policy-billed Skipped/Absent charge — itemised so every rupee of the
    // Net Total is accounted for on screen.
    final presentTotal = b.values.fold<int>(0, (s, v) => s + v);
    final policyBilled = _mealsBill - presentTotal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          ...b.entries.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key, style: AppTypography.bodySmall)),
                    Text('₹${e.value}',
                        style: AppTypography.bodySmall
                            .copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              )),
          // ISSUE-4: Bill-Skip policy charges as their own line (only when the
          // policy actually billed something this period).
          if (policyBilled > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                      child: Text('Skipped/Absent (billed by policy)',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.skipped))),
                  Text('₹$policyBilled',
                      style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.skipped)),
                ],
              ),
            ),
          // Same structure as the member's own My Billing breakdown, so admin
          // and member always reconcile line-by-line to the same net figure.
          // CREDIT-001: carried-forward opening balance — already included in
          // the Net Total (transparency line).
          if (widget.openingBalance != 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                      child: Text(
                          widget.openingBalance > 0
                              ? 'Opening balance (dues carried forward)'
                              : 'Opening balance (credit carried forward)',
                          style: AppTypography.bodySmall.copyWith(
                              color: widget.openingBalance > 0
                                  ? AppColors.warning
                                  : AppColors.present))),
                  Text(
                      '${widget.openingBalance > 0 ? '+' : '−'}₹${widget.openingBalance.abs()}',
                      style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: widget.openingBalance > 0
                              ? AppColors.warning
                              : AppColors.present)),
                ],
              ),
            ),
          if (widget.guestAmount != 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(
                      child: Text('Hosted guests (${widget.guestCount})',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.secondary))),
                  Text('₹${widget.guestAmount}',
                      style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary)),
                ],
              ),
            ),
          // Live-Test-5 ISSUE-4: Debits / Credits / Refunds as independent
          // line items (never merged). Falls back to the single signed
          // adjustments line only when the itemised fields are absent.
          if (widget.debitsTotal != 0)
            _ledgerLine('Debits (approved charges)',
                '+₹${widget.debitsTotal}', AppColors.warning),
          if (widget.creditsTotal != 0)
            _ledgerLine('Credits', '−₹${widget.creditsTotal}',
                AppColors.present),
          if (widget.refundsTotal != 0)
            _ledgerLine('Refunds (cash returned)',
                '+₹${widget.refundsTotal}', AppColors.warning),
          if (widget.adjustmentsTotal != 0 &&
              widget.debitsTotal == 0 &&
              widget.creditsTotal == 0 &&
              widget.refundsTotal == 0)
            _ledgerLine(
                'Adjustments (credits / refunds)',
                '${widget.adjustmentsTotal > 0 ? '+' : '−'}₹${widget.adjustmentsTotal.abs()}',
                widget.adjustmentsTotal > 0
                    ? AppColors.warning
                    : AppColors.present),
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(_hasFinancialExtras ? 'Net Total' : 'Grand Total',
                    style: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w800)),
              ),
              Text(_rupees(_netBill),
                  style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ledgerLine(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
                child: Text(label,
                    style:
                        AppTypography.bodySmall.copyWith(color: color))),
            Text(value,
                style: AppTypography.bodySmall
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  Widget _timelineTile(ColorScheme cs, BillingRow r) {
    final meal = _mealById[r.mealId];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.present.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.present),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.mealName}  ·  ${_fmtDate(r.date)}',
                    style: AppTypography.labelMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                Text(
                  'Attendance ${_fmtTime(r.markedAt)}'
                  '${r.preference != null ? '  ·  ${r.preference}' : ''}',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textTertiary),
                ),
                if (meal != null)
                  Text(
                    'Window ${TimeFormat.window12(meal.attendanceWindow.openTime, meal.attendanceWindow.closeTime)}',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
              ],
            ),
          ),
          if (widget.pricingEnabled)
            Text('₹${r.price ?? 0}',
                style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w800, color: AppColors.primary)),
        ],
      ),
    );
  }

  String _statusText(BillingRow r) {
    switch (r.status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.skipped:
        // ISSUE-4: distinguish the unbilled placeholder from a real record
        // billed by the Bill-Skip policy.
        if (r.autoSkipped) return 'Skipped (auto)';
        return _isPolicyBilled(r) ? 'Skipped (billed)' : 'Skipped';
      default:
        return '—';
    }
  }

  Color _statusColor(BillingRow r) {
    switch (r.status) {
      case AttendanceStatus.present:
        return AppColors.present;
      case AttendanceStatus.absent:
        return AppColors.absent;
      case AttendanceStatus.skipped:
        return AppColors.skipped;
      default:
        return AppColors.textTertiary;
    }
  }
}

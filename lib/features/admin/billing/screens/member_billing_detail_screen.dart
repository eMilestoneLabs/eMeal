import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

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
    final recRes = await _attendanceRepo.getAttendanceHistory(
      userId: widget.userId,
      groupId: widget.groupId,
      organizationId: widget.organizationId,
      from: widget.from,
      to: widget.to,
      params: const PaginationParams(page: 1, limit: 100),
    );
    final mealRes = await _mealRepo.getGroupMeals(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );
    // Issue 3: today's effective (published per-day) windows/prices so the
    // virtual auto-skip never fires while today's real window is still open.
    final todayRes = await _mealRepo.getTodayMeals(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );
    // Issue 7: members currently in Vacation Mode are excluded from attendance
    // calculations — never synthesise a virtual auto-skip for them.
    final membersRes = await _groupRepo.getGroupMembers(
      organizationId: widget.organizationId,
      groupId: widget.groupId,
    );

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
    final summaries = BillingService.summarize(rows);

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
          );
        case 'csv':
          await svc.exportCsv(
            records: _records,
            meals: _meals,
            groupName: name,
            pricingEnabled: widget.pricingEnabled,
            from: widget.from,
            to: widget.to,
            dateRangeLabel: label,
            todayMeals: _todayMeals,
            vacationUserIds: _vacationUserIds,
          );
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
    final bill = _summary?.totalBill ?? 0;
    return days == 0 ? 0 : (bill / days).round();
  }

  String _fmtDate(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  String _fmtTime(DateTime? d) => d == null
      ? '—'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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
                    PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                  ],
                ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
            Text('Total Bill',
                style: AppTypography.labelSmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.85))),
            Text('₹${_summary?.totalBill ?? 0}',
                style: AppTypography.numericMedium.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }

  Widget _statsGrid(ColorScheme cs) {
    final s = _summary;
    final items = <List<String>>[
      ['Present', '${s?.present ?? 0}'],
      ['Skipped', '${s?.skipped ?? 0}'],
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

  Widget _dateGroup(ColorScheme cs, DateTime date, List<BillingRow> rows) {
    final subtotal = rows
        .where((r) => r.isPresent)
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
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.mealName, style: AppTypography.bodySmall),
                    ),
                    Text(_statusText(r),
                        style: AppTypography.labelSmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _statusColor(r))),
                    if (widget.pricingEnabled && r.isPresent) ...[
                      const SizedBox(width: 10),
                      Text('₹${r.price ?? 0}',
                          style: AppTypography.labelSmall
                              .copyWith(fontWeight: FontWeight.w700)),
                    ],
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
          const Divider(height: 18),
          Row(
            children: [
              Expanded(
                child: Text('Grand Total',
                    style: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w800)),
              ),
              Text('₹${_summary?.totalBill ?? 0}',
                  style: AppTypography.titleSmall.copyWith(
                      fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }

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
                    'Window ${meal.attendanceWindow.openTime}'
                    ' – ${meal.attendanceWindow.closeTime}',
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
        return r.autoSkipped ? 'Skipped (auto)' : 'Skipped';
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

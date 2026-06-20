import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/paginated_response.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Admin per-member billing (req 7).
///
/// Pick a group + a range preset (Daily / Weekly / Monthly / Custom) and the
/// screen computes each member's itemised meal consumption and total payable
/// from the existing attendance records + meal prices, via [BillingService].
/// Only PRESENT meals contribute to the bill; un-marked closed windows are
/// counted as auto-skipped (no charge).
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

enum _RangePreset { daily, weekly, monthly, custom }

class _BillingScreenState extends State<BillingScreen> {
  final _groupRepo = GroupRepository();
  final _attendanceRepo = AttendanceRepository();
  final _mealRepo = MealRepository();

  List<GroupModel> _groups = [];
  String? _groupId;
  bool _loadingGroups = true;
  bool _loading = false;
  bool _initialized = false;

  _RangePreset _preset = _RangePreset.monthly;
  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to = DateTime.now();

  List<BillingSummary> _summaries = [];
  List<BillingRow> _rows = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _loadGroups();
    }
  }

  Future<void> _loadGroups() async {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) return;
    final res =
        await _groupRepo.getOrganisationGroups(organizationId: user.organizationId);
    if (!mounted) return;
    setState(() {
      _loadingGroups = false;
      if (res case Ok(:final value)) {
        _groups = value.data;
        _groupId = _groups.isNotEmpty ? _groups.first.id : null;
      }
    });
    if (_groupId != null) _compute();
  }

  void _applyPreset(_RangePreset p) {
    final now = DateTime.now();
    setState(() {
      _preset = p;
      switch (p) {
        case _RangePreset.daily:
          _from = DateTime(now.year, now.month, now.day);
          _to = now;
        case _RangePreset.weekly:
          _from = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          _to = now;
        case _RangePreset.monthly:
          _from = DateTime(now.year, now.month, 1);
          _to = now;
        case _RangePreset.custom:
          break;
      }
    });
    if (p != _RangePreset.custom) _compute();
  }

  bool get _pricingEnabled {
    if (_groupId == null) return false;
    try {
      return _groups
          .firstWhere((g) => g.id == _groupId)
          .mealConfig
          .mealPricingEnabled;
    } catch (_) {
      return false;
    }
  }

  Future<void> _compute() async {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null || _groupId == null) return;
    setState(() => _loading = true);

    final recRes = await _attendanceRepo.getAttendanceHistory(
      userId: '',
      groupId: _groupId!,
      organizationId: user.organizationId,
      from: _from,
      to: _to,
      params: const PaginationParams(page: 1, limit: 100),
    );
    final mealRes = await _mealRepo.getGroupMeals(
      organizationId: user.organizationId,
      groupId: _groupId!,
    );

    List<AttendanceModel> records = [];
    if (recRes case Ok(:final value)) records = value.data;
    List<MealModel> meals = [];
    if (mealRes case Ok(:final value)) meals = value;

    final rows = BillingService.buildRows(
      records: records,
      meals: meals,
      from: _from,
      to: _to,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _summaries = BillingService.summarize(rows);
      _loading = false;
    });
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
        _preset = _RangePreset.custom;
        _from = picked.start;
        _to = picked.end;
      });
      _compute();
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Member Billing', style: AppTypography.titleLarge),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loadingGroups
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_groups.length > 1) ...[
                    _GroupDropdown(
                      groups: _groups,
                      selectedId: _groupId,
                      onChanged: (id) {
                        setState(() => _groupId = id);
                        _compute();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  _PresetRow(
                    preset: _preset,
                    onSelect: (p) =>
                        p == _RangePreset.custom ? _pickCustom() : _applyPreset(p),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_fmt(_from)} – ${_fmt(_to)}',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _summaries.isEmpty
                            ? Center(
                                child: Text('No attendance in this range.',
                                    style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.textTertiary)),
                              )
                            : ListView.separated(
                                itemCount: _summaries.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, i) => _MemberBillCard(
                                  summary: _summaries[i],
                                  pricingEnabled: _pricingEnabled,
                                  onTap: () => _showItemized(_summaries[i]),
                                ),
                              ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showItemized(BillingSummary s) {
    final rows =
        _rows.where((r) => r.userId == s.userId).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          children: [
            Text(s.userName,
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (_pricingEnabled)
              Text('Total Bill: ₹${s.totalBill}',
                  style: AppTypography.titleSmall.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${r.mealName} · ${_fmt(r.date)}',
                          style: AppTypography.bodySmall,
                        ),
                      ),
                      Text(
                        _statusText(r),
                        style: AppTypography.labelSmall.copyWith(
                          fontWeight: FontWeight.w700,
                          color: _statusColor(r),
                        ),
                      ),
                      if (_pricingEnabled && r.isPresent) ...[
                        const SizedBox(width: 10),
                        Text('₹${r.price ?? 0}',
                            style: AppTypography.labelSmall
                                .copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ],
                  ),
                )),
          ],
        ),
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

class _GroupDropdown extends StatelessWidget {
  const _GroupDropdown(
      {required this.groups, required this.selectedId, required this.onChanged});
  final List<GroupModel> groups;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedId,
          isExpanded: true,
          items: groups
              .map((g) => DropdownMenuItem(
                  value: g.id,
                  child: Text(g.name, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PresetRow extends StatelessWidget {
  const _PresetRow({required this.preset, required this.onSelect});
  final _RangePreset preset;
  final ValueChanged<_RangePreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget chip(String label, _RangePreset p) {
      final sel = preset == p;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelect(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.primary
                    : colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: sel
                      ? AppColors.primary
                      : AppColors.border,
                  width: 1,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (sel) ...[
                    const Icon(Icons.check_rounded,
                        size: 15, color: Colors.white),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: sel ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          chip('Today', _RangePreset.daily),
          chip('This Week', _RangePreset.weekly),
          chip('This Month', _RangePreset.monthly),
          chip('Custom', _RangePreset.custom),
        ],
      ),
    );
  }
}

class _MemberBillCard extends StatelessWidget {
  const _MemberBillCard(
      {required this.summary,
      required this.pricingEnabled,
      required this.onTap});
  final BillingSummary summary;
  final bool pricingEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.userName,
                        style: AppTypography.labelLarge
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Present ${summary.present} · Skipped ${summary.skipped} · Absent ${summary.absent}',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (pricingEnabled)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('₹${summary.totalBill}',
                        style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                    Text('Total bill',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

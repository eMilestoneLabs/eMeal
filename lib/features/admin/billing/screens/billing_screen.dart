import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/billing/providers/member_billing_provider.dart';
import 'package:smart_meal_management/features/admin/billing/screens/member_billing_detail_screen.dart';
import 'package:smart_meal_management/features/admin/billing/widgets/billing_adjustments_sheet.dart';
import 'package:smart_meal_management/features/admin/billing/widgets/billing_periods_sheet.dart';
import 'package:smart_meal_management/shared/widgets/app_screen_states.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/models/billing_summary.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Member Billing V2 — premium fintech-style billing dashboard (admin).
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final MemberBillingProvider _provider = MemberBillingProvider();
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final user = AuthProviderScope.of(context).currentUser;
    if (user != null) _provider.init(user);
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange:
          DateTimeRange(start: _provider.from, end: _provider.to),
    );
    if (picked != null) _provider.setCustomRange(picked.start, picked.end);
  }

  void _openMember(BillingMemberRow m) {
    final user = AuthProviderScope.of(context).currentUser;
    if (user == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MemberBillingDetailScreen(
          userId: m.userId,
          userName: m.userName,
          role: m.role,
          groupId: _provider.groupId ?? '',
          organizationId: user.organizationId,
          groupName: _provider.selectedGroup?.name ?? '',
          from: _provider.from,
          to: _provider.to,
          pricingEnabled: _provider.pricingEnabled,
          // SRS Module 03 (survey Q17/Q22): group Bill-Skip policy.
          billSkippedMeals:
              _provider.selectedGroup?.mealConfig.billSkippedMeals ?? false,
          // Billing-consistency fix: hand over the guest + adjustment figures
          // so the detail headline is the same net bill this list shows.
          guestCount: m.guestCount,
          guestAmount: m.guestAmount,
          adjustmentsTotal: m.adjustmentsTotal,
          // CREDIT-001: carried-forward balance rides along so the detail
          // headline matches this list's netBill exactly.
          openingBalance: m.openingBalance,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Member Billing', style: AppTypography.titleLarge),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          // Pass 12 (FR-BILLX-030/031): append-only credit/debit/refund ledger.
          ListenableBuilder(
            listenable: _provider,
            builder: (context, _) => IconButton(
              tooltip: 'Billing adjustments (credits / refunds)',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: _provider.groupId == null
                  ? null
                  : () => BillingAdjustmentsSheet.show(
                        context,
                        groupId: _provider.groupId!,
                        members: _provider.summary.members,
                        onChanged: _provider.compute,
                      ),
            ),
          ),
          // SRS FR-DISP-010 (Pass 7): finalize / reopen billing periods.
          ListenableBuilder(
            listenable: _provider,
            builder: (context, _) => IconButton(
              tooltip: 'Billing periods (finalize / reopen)',
              icon: const Icon(Icons.lock_clock_rounded),
              onPressed: _provider.groupId == null
                  ? null
                  : () => BillingPeriodsSheet.show(
                        context,
                        groupId: _provider.groupId!,
                        from: _provider.from,
                        to: _provider.to,
                      ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _provider,
        builder: (context, _) {
          if (_provider.loadingGroups) {
            return const AppDashboardSkeleton();
          }
          if (_provider.groups.isEmpty) {
            return Center(
              child: Text('No groups yet.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textTertiary)),
            );
          }
          return LayoutBuilder(
            builder: (context, c) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _GroupSelector(
                    groups: _provider.groups,
                    selected: _provider.selectedGroup,
                    onSelect: _provider.selectGroup,
                  ),
                  const SizedBox(height: 14),
                  _PeriodSelector(
                    period: _provider.period,
                    onSelect: (p) => p == BillingPeriod.custom
                        ? _pickCustom()
                        : _provider.setPeriod(p),
                  ),
                  const SizedBox(height: 6),
                  Text(
                      '${_fmt(_provider.from)} – ${_fmt(_provider.to)}'
                      // Pass 12 (FR-BILLX-020): show the configured cycle.
                      '${(_provider.summary.cycleStartDay ?? 1) > 1 ? ' · cycle starts day ${_provider.summary.cycleStartDay}' : ''}',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textTertiary)),
                  const SizedBox(height: 14),
                  _summaryCards(cs, c.maxWidth),
                  const SizedBox(height: 18),
                  // Issue 4: while the billing summary + series are loading, show
                  // a loader for the analytics region instead of letting the
                  // charts flash "No data for this range." before data arrives.
                  if (_provider.loading) ...[
                    const _BillingAnalyticsLoading(),
                    const SizedBox(height: 18),
                  ] else ...[
                    if (_provider.pricingEnabled &&
                        _provider.summary.mealBreakdown.isNotEmpty) ...[
                      _RevenueChartCard(
                          breakdown: _provider.summary.mealBreakdown),
                      const SizedBox(height: 18),
                    ],
                    if (_provider.pricingEnabled) ...[
                      _AnalyticsSection(provider: _provider),
                      const SizedBox(height: 18),
                    ],
                  ],
                  _controlsRow(cs),
                  const SizedBox(height: 12),
                  if (_provider.loading)
                    // ES-004 (Pass 13): layout-stable skeleton — same card
                    // heights as the member list, so nothing jumps.
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: AppSkeletonList(rows: 4, rowHeight: 88),
                    )
                  else if (_provider.error != null)
                    // ES-003 (Pass 13): retry re-runs compute() with the
                    // CURRENT group/period/sort/search — nothing is reset.
                    AppErrorState(
                      compact: true,
                      message: _provider.error,
                      onRetry: _provider.compute,
                    )
                  else if (_provider.visibleMembers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(EmptyCopy.noBillingData,
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.textTertiary)),
                      ),
                    )
                  else
                    ..._provider.visibleMembers.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MemberCard(
                            member: m,
                            pricingEnabled: _provider.pricingEnabled,
                            onTap: () => _openMember(m),
                          ),
                        )),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _summaryCards(ColorScheme cs, double width) {
    final s = _provider.summary;
    final cards = <Widget>[
      _SummaryCard(
        // Module 22 (FR-HG-050): guest revenue is itemised inside the total.
        // Pass 12 (FR-BILLX-030): ledger adjustments surface as NET revenue.
        // Short label (the long "(adj −₹…)" suffix truncated on phones); the
        // gross + adjustment components live in the subline instead.
        label: s.adjustmentsTotal != 0 ? 'Net Revenue' : 'Revenue',
        sub: s.adjustmentsTotal != 0
            ? 'gross ${cur(s.revenue)} · adj ${s.adjustmentsTotal > 0 ? '+' : '−'}${cur(s.adjustmentsTotal.abs())}'
            : (s.guestRevenue > 0
                ? 'incl. ${cur(s.guestRevenue)} guests'
                : null),
        value: cur(s.adjustmentsTotal != 0 ? s.netRevenue : s.revenue),
        icon: Icons.payments_rounded,
        accent: AppColors.present,
      ),
      _SummaryCard(
        label: 'Members',
        value: '${s.memberCount}',
        icon: Icons.groups_rounded,
        accent: AppColors.primary,
      ),
      _SummaryCard(
        label: 'Present Meals',
        value: '${s.presentMeals}',
        icon: Icons.restaurant_rounded,
        accent: AppColors.info,
      ),
      _SummaryCard(
        label: 'Average Bill',
        value: cur(s.averageBill),
        icon: Icons.trending_up_rounded,
        accent: AppColors.warning,
      ),
    ];

    if (width >= 720) {
      return Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }

    if (width >= 480) {
      Widget row(Widget a, Widget b) => Row(
            children: [
              Expanded(child: a),
              const SizedBox(width: 12),
              Expanded(child: b),
            ],
          );
      return Column(
        children: [
          row(cards[0], cards[1]),
          const SizedBox(height: 12),
          row(cards[2], cards[3]),
        ],
      );
    }

    return SizedBox(
      // 110 (was 96): room for the net-revenue components subline without
      // overflowing the fixed-height horizontal strip.
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: 160, child: cards[i]),
      ),
    );
  }

  Widget _controlsRow(ColorScheme cs) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded,
                    size: 18, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: _provider.setSearch,
                    style: AppTypography.bodySmall,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search name / email / phone',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<BillingSort>(
              value: _provider.sort,
              isDense: true,
              icon: const Icon(Icons.sort_rounded, size: 18),
              style: AppTypography.labelSmall
                  .copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
              items: const [
                DropdownMenuItem(
                    value: BillingSort.highestBill, child: Text('Highest bill')),
                DropdownMenuItem(
                    value: BillingSort.lowestBill, child: Text('Lowest bill')),
                DropdownMenuItem(
                    value: BillingSort.mostMeals, child: Text('Most meals')),
                DropdownMenuItem(
                    value: BillingSort.leastMeals, child: Text('Least meals')),
                DropdownMenuItem(value: BillingSort.name, child: Text('Name')),
                DropdownMenuItem(
                    value: BillingSort.newest, child: Text('Newest')),
                DropdownMenuItem(
                    value: BillingSort.oldest, child: Text('Oldest')),
              ],
              onChanged: (v) {
                if (v != null) _provider.setSort(v);
              },
            ),
          ),
        ),
      ],
    );
  }
}

// Negative-safe: ₹-962 reads badly, -₹962 reads like money owed back.
String cur(int v) => v < 0 ? '-₹${-v}' : '₹$v';

// Summary card
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.sub,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  /// Optional secondary line (e.g. gross + adjustments behind a net figure).
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: accent),
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
          if (sub != null)
            Text(sub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall
                    .copyWith(color: AppColors.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }
}

// Period selector
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.period, required this.onSelect});
  final BillingPeriod period;
  final ValueChanged<BillingPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String label, BillingPeriod p) {
      final sel = period == p;
      return Expanded(
        child: GestureDetector(
          onTap: () => onSelect(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: sel ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (sel) ...[
                  const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: sel ? Colors.white : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          seg('Today', BillingPeriod.today),
          seg('Week', BillingPeriod.week),
          seg('Month', BillingPeriod.month),
          seg('Custom', BillingPeriod.custom),
        ],
      ),
    );
  }
}

// Group selector (searchable)
Widget _groupAvatar(String name, {double size = 38}) {
  final initials = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    child: Text(initials,
        style: AppTypography.titleSmall.copyWith(
            color: AppColors.primary, fontWeight: FontWeight.w800)),
  );
}

class _GroupSelector extends StatelessWidget {
  const _GroupSelector(
      {required this.groups, required this.selected, required this.onSelect});
  final List<GroupModel> groups;
  final GroupModel? selected;
  final ValueChanged<String?> onSelect;

  void _openPicker(BuildContext context) {
    if (groups.length <= 1) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GroupPickerSheet(
        groups: groups,
        selectedId: selected?.id,
        onSelect: (id) {
          Navigator.of(context).pop();
          onSelect(id);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = selected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openPicker(context),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              _groupAvatar(g?.name ?? '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g?.name ?? 'Select group',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge
                            .copyWith(fontWeight: FontWeight.w700)),
                    if (g != null)
                      Text('${g.memberCount} members',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              if (groups.length > 1)
                const Icon(Icons.unfold_more_rounded,
                    color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupPickerSheet extends StatefulWidget {
  const _GroupPickerSheet(
      {required this.groups, required this.selectedId, required this.onSelect});
  final List<GroupModel> groups;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.groups
        : widget.groups
            .where((g) => g.name.toLowerCase().contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, ctrl) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.textTertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setState(() => _q = v),
                      style: AppTypography.bodyMedium,
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search group',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final g = list[i];
                  final sel = g.id == widget.selectedId;
                  return ListTile(
                    leading: _groupAvatar(g.name, size: 40),
                    title: Text(g.name,
                        style: AppTypography.labelLarge
                            .copyWith(fontWeight: FontWeight.w700)),
                    subtitle: Text('${g.memberCount} members',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textTertiary)),
                    trailing: sel
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary)
                        : null,
                    onTap: () => widget.onSelect(g.id),
                  );
                },
              ),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }
}

// Revenue-by-meal chart
class _RevenueChartCard extends StatelessWidget {
  const _RevenueChartCard({required this.breakdown});
  final List<BillingMealBreakdown> breakdown;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = breakdown.take(6).toList();
    final maxY = items.fold<int>(0, (m, e) => e.revenue > m ? e.revenue : m);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Revenue by meal',
              style: AppTypography.titleSmall
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxY == 0 ? 1 : maxY) * 1.2,
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= items.length) {
                          return const SizedBox.shrink();
                        }
                        final name = items[i].mealName;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            name.length > 6 ? name.substring(0, 6) : name,
                            style: AppTypography.labelSmall.copyWith(
                                fontSize: 9, color: AppColors.textTertiary),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < items.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: items[i].revenue.toDouble(),
                          width: 18,
                          color: AppColors.primary,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Member card
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.pricingEnabled,
    required this.onTap,
  });
  final BillingMemberRow member;
  final bool pricingEnabled;
  final VoidCallback onTap;

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              _groupAvatar(member.userName, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(member.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge
                                  .copyWith(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 6),
                        _RolePill(role: member.role),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Present ${member.presentCount} · Skipped ${member.skippedCount} · Absent ${member.absentCount}',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    // Module 22 (FR-HG-053, Pass 9): hosted-guest charges are
                    // itemised so the member's bill is explainable at a glance.
                    if (member.guestCount > 0)
                      Text(
                        'Guests ${member.guestCount}'
                        '${pricingEnabled ? ' · ${cur(member.guestAmount)} of bill' : ''}',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.secondary),
                      ),
                    // Pass 12 (FR-BILLX-012/030): vacation days + signed
                    // ledger adjustments — the bill is explainable at a glance.
                    if (member.vacationDays > 0)
                      Text(
                        'On vacation ${member.vacationDays} meal(s) — not billed',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.vacation),
                      ),
                    // CREDIT-001: carried-forward balance, explainable at a
                    // glance (already inside the net headline).
                    if (pricingEnabled && member.openingBalance != 0)
                      Text(
                        'Opening ${member.openingBalance > 0 ? '+' : '−'}'
                        '${cur(member.openingBalance.abs())} carried forward',
                        style: AppTypography.labelSmall.copyWith(
                          color: member.openingBalance > 0
                              ? AppColors.warning
                              : AppColors.present,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (pricingEnabled && member.adjustmentsTotal != 0)
                      Text(
                        'Adjustments ${member.adjustmentsTotal > 0 ? '+' : '−'}'
                        '${cur(member.adjustmentsTotal.abs())}',
                        style: AppTypography.labelSmall.copyWith(
                          color: member.adjustmentsTotal > 0
                              ? AppColors.warning
                              : AppColors.present,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text('Last activity: ${_fmtDate(member.lastActivity)}',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Billing-consistency fix: the headline is the NET bill
                  // (meals + guests + adjustments) — the same figure the
                  // member sees on My Billing and the sum behind the Net
                  // Revenue card. Gross stays visible right below.
                  if (pricingEnabled) ...[
                    Text(cur(member.netBill),
                        style: AppTypography.titleSmall.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                    if (member.netBill != member.totalBill)
                      Text('gross ${cur(member.totalBill)}',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.textTertiary)),
                  ],
                  const SizedBox(height: 2),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textTertiary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(role,
          style: AppTypography.labelSmall
              .copyWith(color: AppColors.info, fontWeight: FontWeight.w600)),
    );
  }
}


// ── Analytics section (Gap 3): revenue trend, meals consumed, member spend ───

class _AnalyticsSection extends StatelessWidget {
  const _AnalyticsSection({required this.provider});
  final MemberBillingProvider provider;

  String _short(String label) =>
      label.length >= 5 ? label.substring(5) : label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = provider.series.points;
    final topMembers = provider.summary.members.take(6).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Analytics',
                    style: AppTypography.titleSmall
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
              _BucketToggle(
                bucket: provider.bucket,
                onSelect: provider.setBucket,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Revenue trend',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: pts.isEmpty
                ? _emptyChart()
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (pts.fold<int>(
                                  0, (m, e) => e.revenue > m ? e.revenue : m) ==
                              0
                          ? 1
                          : pts.fold<int>(
                              0, (m, e) => e.revenue > m ? e.revenue : m) *
                              1.2),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      titlesData: _bottomTitles(pts.map((e) => _short(e.label)).toList()),
                      barGroups: [
                        for (var i = 0; i < pts.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: pts[i].revenue.toDouble(),
                              width: 14,
                              color: AppColors.primary,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                            ),
                          ]),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          Text('Meals consumed',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          SizedBox(
            height: 130,
            child: pts.isEmpty
                ? _emptyChart()
                : LineChart(
                    LineChartData(
                      minY: 0,
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      titlesData: _bottomTitles(pts.map((e) => _short(e.label)).toList()),
                      lineBarsData: [
                        LineChartBarData(
                          spots: [
                            for (var i = 0; i < pts.length; i++)
                              FlSpot(i.toDouble(), pts[i].presentMeals.toDouble()),
                          ],
                          isCurved: true,
                          color: AppColors.secondary,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppColors.secondary.withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          Text('Top member spending',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: topMembers.isEmpty
                ? _emptyChart()
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (topMembers.fold<int>(0,
                                  (m, e) => e.totalBill > m ? e.totalBill : m) ==
                              0
                          ? 1
                          : topMembers.fold<int>(0,
                                  (m, e) => e.totalBill > m ? e.totalBill : m) *
                              1.2),
                      borderData: FlBorderData(show: false),
                      gridData: const FlGridData(show: false),
                      titlesData: _bottomTitles(topMembers
                          .map((m) => m.userName.split(' ').first)
                          .toList()),
                      barGroups: [
                        for (var i = 0; i < topMembers.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: topMembers[i].totalBill.toDouble(),
                              width: 16,
                              color: AppColors.warning,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5)),
                            ),
                          ]),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyChart() => Center(
        child: Text('No data for this range.',
            style: AppTypography.labelSmall
                .copyWith(color: AppColors.textTertiary)),
      );

  FlTitlesData _bottomTitles(List<String> labels) => FlTitlesData(
        leftTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= labels.length) return const SizedBox.shrink();
              // Thin out labels when there are many buckets.
              final step = (labels.length / 6).ceil();
              if (step > 1 && i % step != 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(labels[i],
                    style: AppTypography.labelSmall
                        .copyWith(fontSize: 8, color: AppColors.textTertiary)),
              );
            },
          ),
        ),
      );
}

class _BucketToggle extends StatelessWidget {
  const _BucketToggle({required this.bucket, required this.onSelect});
  final BillingBucket bucket;
  final ValueChanged<BillingBucket> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget seg(String label, BillingBucket b) {
      final sel = bucket == b;
      return GestureDetector(
        onTap: () => onSelect(b),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: AppTypography.labelSmall.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : AppColors.textSecondary,
              )),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('Day', BillingBucket.day),
        seg('Week', BillingBucket.week),
        seg('Month', BillingBucket.month),
      ]),
    );
  }
}


/// Issue 4: lightweight loader card for the billing analytics region, shown
/// while the summary + series requests are in flight so the charts never flash
/// an empty "No data for this range." state before data arrives.
class _BillingAnalyticsLoading extends StatelessWidget {
  const _BillingAnalyticsLoading();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.4),
        ),
      ),
      child: const AppChartSkeleton(height: 148, padding: EdgeInsets.all(16)),
    );
  }
}

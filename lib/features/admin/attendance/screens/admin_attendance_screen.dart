import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/features/admin/attendance/providers/admin_attendance_provider.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/correction_requests_screen.dart';
import 'package:smart_meal_management/features/admin/attendance/screens/vacation_requests_screen.dart';
import 'package:smart_meal_management/features/admin/attendance/widgets/admin_guests_sheet.dart';
import 'package:smart_meal_management/features/admin/attendance/widgets/attendance_filter_bar.dart';
import 'package:smart_meal_management/features/admin/attendance/widgets/member_attendance_row.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/guest_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/shared/widgets/preference_group_selector.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Admin screen for viewing group attendance on a specific date.
///
/// Includes a group selector so admins managing multiple groups can switch
/// context without leaving the screen.
class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key, this.autoOpen});

  /// Live-Test-11 ISSUE-001: notification deep-link intent. When opened from a
  /// bell/tray notification this jumps straight into the actual approval UI:
  /// 'guests' → hosted-guest approvals sheet (once group context loads),
  /// 'corrections' → Correction Requests queue, 'vacations' → Vacation
  /// Requests queue. Null = normal attendance screen.
  final String? autoOpen;

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  late final AdminAttendanceProvider _provider;
  final GroupRepository _groupRepo = GroupRepository();

  bool _initialized = false;
  bool _loadingGroups = false;
  List<GroupModel> _groups = [];
  String? _selectedGroupId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _provider = AdminAttendanceProvider();
      _provider.addListener(_rebuild);
      _loadGroups();
      // ISSUE-001: corrections/vacations queues need no group context — open
      // them immediately so the notification tap lands on the approval UI.
      final open = widget.autoOpen;
      if (open == 'corrections' || open == 'vacations') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => open == 'corrections'
                ? const CorrectionRequestsScreen()
                : const VacationRequestsScreen(),
          ));
        });
      }
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _loadGroups() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) {
      setState(() => _loadingGroups = false);
      return;
    }
    final orgId = user.organizationId;

    String? resolveSelected(List<GroupModel> groups) {
      final userGroupId = auth.currentUser?.effectiveGroupIds.firstOrNull;
      final match = groups.any((g) => g.id == userGroupId);
      return match ? userGroupId : (groups.isNotEmpty ? groups.first.id : null);
    }

    // Cache-first: paint the group selector + start attendance from the
    // last-known groups instantly (shared 'admin_groups:$org' cache), so
    // returning to this tab never blocks on a fresh groups round-trip first.
    if (_groups.isEmpty) {
      // Miss-vs-empty aware: a cached EMPTY org (no groups yet) paints its
      // real empty state instantly; only a true cache MISS shows the loader.
      final cached = await ResponseCacheService.instance.readListOrNull(
          'admin_groups:$orgId', GroupModel.fromJson,
          maxAge: const Duration(hours: 12));
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _groups = cached;
          _selectedGroupId = resolveSelected(cached);
          _loadingGroups = false;
        });
        // Start attendance WITHOUT awaiting so the groups refresh below runs in
        // the SAME network wave — tap-to-fully-fresh costs one round-trip, not
        // two sequential ones. The prevSel check below still prevents a
        // duplicate attendance fetch when the resolved group is unchanged.
        if (_selectedGroupId != null) unawaited(_loadAttendance(orgId));
        _maybeAutoOpenGuests();
      } else {
        setState(() => _loadingGroups = true);
      }
    }

    final result = await _groupRepo.getOrganisationGroups(
      organizationId: orgId,
    );

    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        final groups = value.data;
        ResponseCacheService.instance
            .writeList('admin_groups:$orgId', groups, (g) => g.toJson());
        final prevSel = _selectedGroupId;
        setState(() {
          _groups = groups;
          _loadingGroups = false;
          _selectedGroupId = resolveSelected(groups);
        });
        // Only (re)load attendance here if the cache path hadn't already, or the
        // resolved group changed — avoids a duplicate attendance fetch warm.
        if (_selectedGroupId != null && _selectedGroupId != prevSel) {
          await _loadAttendance(orgId);
        }
        _maybeAutoOpenGuests();
      case Err():
        setState(() => _loadingGroups = false);
    }
  }

  /// ISSUE-001: one-shot — opens the guest approvals sheet when this screen
  /// was reached from a guest-request notification and guests are enabled.
  bool _autoOpenedGuests = false;
  void _maybeAutoOpenGuests() {
    if (widget.autoOpen != 'guests' || _autoOpenedGuests) return;
    if (_selectedGroupId == null) return;
    final group = _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
    if (group == null || !group.mealConfig.guestsEnabled) return;
    _autoOpenedGuests = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openGuests();
    });
  }

  Future<void> _loadAttendance(String orgId) async {
    if (_selectedGroupId == null) return;
    final guestsOn = _groups
            .where((g) => g.id == _selectedGroupId)
            .firstOrNull
            ?.mealConfig
            .guestsEnabled ??
        false;
    await _provider.load(
      groupId: _selectedGroupId!,
      organizationId: orgId,
      guestsEnabled: guestsOn,
    );
  }

  Future<void> _onGroupChanged(String? groupId) async {
    if (groupId == null || groupId == _selectedGroupId) return;
    setState(() => _selectedGroupId = groupId);
    final orgId = AuthProviderScope.of(context).currentUser?.organizationId;
    if (orgId == null) return;
    await _loadAttendance(orgId);
  }

  Future<void> _pickDate() async {
    final auth = AuthProviderScope.of(context);
    final picked = await showDatePicker(
      context: context,
      initialDate: _provider.selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _provider.setDate(picked);
      if (!mounted) return;
      final orgId = auth.currentUser?.organizationId;
      if (orgId == null) return;
      await _loadAttendance(orgId);
    }
  }

  /// SRS Module 03 ATT-004: attendance ownership belongs to the member —
  /// admins can no longer change a member's record. Tapping a record explains
  /// the Correction Request workflow and deep-links to the review queue.
  Future<void> _showOwnershipInfo(AttendanceModel record) async {
    final name = record.mealName ?? 'this meal';
    final goToQueue = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attendance belongs to the member'),
        content: Text(
          'Admins cannot mark or edit member attendance for $name. '
          'If a change is needed, the member submits an Attendance '
          'Correction Request (Present or Absent + their meal preferences) '
          'and you approve or reject it — the system applies the change '
          'automatically on approval.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Review corrections'),
          ),
        ],
      ),
    );
    if (goToQueue == true && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CorrectionRequestsScreen(),
        ),
      );
    }
  }

  /// Module 22 (Pass 9): hosted-guest management for the selected group+date —
  /// approvals queue, cancellations, and governed add-on-behalf (FR-HG-042/062).
  Future<void> _openGuests() async {
    final user = AuthProviderScope.of(context).currentUser;
    final group = _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
    if (user == null || group == null) return;
    await showAdminGuestsSheet(
      context,
      group: group,
      date: _provider.selectedDate,
      organizationId: user.organizationId,
    );
    if (!mounted) return;
    // Guest changes touch host counters — refresh the attendance list.
    await _loadAttendance(user.organizationId);
  }

  /// Issue 5: opens a sheet where the admin marks their OWN attendance for
  /// today's meals (via the admin override path, which works regardless of the
  /// window and snapshots the effective price). Refreshes the list afterwards.
  Future<void> _openMyAttendance() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null || _selectedGroupId == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MyAttendanceSheet(
        organizationId: user.organizationId,
        groupId: _selectedGroupId!,
        userId: user.id,
        userName: user.name,
      ),
    );
    if (!mounted) return;
    await _loadAttendance(user.organizationId);
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  /// command_3 (#4/#5): dedicated quick-action toolbar. Frequently-used actions
  /// stay immediately accessible (Mark mine, Vacation Approval, Corrections,
  /// Hosted Guests) rather than hidden in an overflow menu.
  Widget _buildQuickActions(bool isDark) {
    final guestsOn = _groups
            .where((g) => g.id == _selectedGroupId)
            .firstOrNull
            ?.mealConfig
            .guestsEnabled ??
        false;
    final actions = <Widget>[
      _QuickActionPill(
        icon: Icons.how_to_reg_rounded,
        label: 'Mark mine',
        color: AppColors.present,
        onTap: _openMyAttendance,
      ),
      _QuickActionPill(
        icon: Icons.beach_access_rounded,
        label: 'Vacation approval',
        color: AppColors.vacation,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const VacationRequestsScreen())),
      ),
      _QuickActionPill(
        icon: Icons.rule_rounded,
        label: 'Corrections',
        color: AppColors.info,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const CorrectionRequestsScreen())),
      ),
      if (guestsOn)
        _QuickActionPill(
          icon: Icons.group_add_rounded,
          label: 'Hosted guests',
          color: AppColors.warning,
          onTap: _openGuests,
        ),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: AppConstants.pagePaddingH),
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => actions[i],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final date = _provider.selectedDate;
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      appBar: AppBar(
        title: Text('Attendance', style: AppTypography.titleLarge),
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        surfaceTintColor: Colors.transparent,
        // command_3 (#4): actions moved OUT of the overflow (⋮) into a dedicated
        // quick-action toolbar in the body (see _buildQuickActions). The appbar
        // keeps just the compact date so the title never truncates to "Att…".
        actions: [
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(dateStr, style: AppTypography.labelMedium),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Group selector ──────────────────────────────────────────────────
          if (_loadingGroups)
            const AppChipRowSkeleton()
          else if (_groups.isNotEmpty)
            _GroupSelectorBar(
              groups: _groups,
              selectedGroupId: _selectedGroupId,
              onChanged: _onGroupChanged,
            ),

          // ── Stats row ───────────────────────────────────────────────────────
          if (!_provider.isLoading && _selectedGroupId != null)
            Container(
              color: isDark ? AppColors.surfaceDark : AppColors.surface,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.pagePaddingH, vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _StatBadge(
                        label: 'Present',
                        count: _provider.presentCount,
                        color: AppColors.present,
                        icon: Icons.check_circle_rounded),
                    const SizedBox(width: 10),
                    _StatBadge(
                        label: 'Absent',
                        count: _provider.absentCount,
                        color: AppColors.absent,
                        icon: Icons.cancel_rounded),
                    const SizedBox(width: 10),
                    _StatBadge(
                        label: 'Pending',
                        count: _provider.pendingCount,
                        color: AppColors.warning,
                        icon: Icons.schedule_rounded),
                    const SizedBox(width: 10),
                    // Issue 4: vacation members tracked separately — they are
                    // NOT counted as present / absent / pending.
                    _StatBadge(
                        label: 'Vacation',
                        count: _provider.vacationCount,
                        color: AppColors.vacation,
                        icon: Icons.beach_access_rounded),
                    // Live-Test-5 (Guest Attendance Visibility policy): guest
                    // meals surfaced separately — never inside Member Present.
                    if (_provider.guests.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      _StatBadge(
                          label: 'Guests',
                          count: _provider.confirmedGuestCount,
                          color: AppColors.secondary,
                          icon: Icons.group_add_rounded),
                      const SizedBox(width: 10),
                      _StatBadge(
                          label: 'Total meals',
                          count: _provider.totalMealsCount,
                          color: AppColors.info,
                          icon: Icons.restaurant_rounded),
                    ],
                  ],
                ),
              ),
            ),

          // ── Quick actions toolbar ───────────────────────────────────────────
          // command_3 (#4/#5): frequently-used admin actions are surfaced here
          // as a dedicated toolbar instead of being buried in the overflow (⋮)
          // menu — including Vacation Approval as a first-class action.
          if (_selectedGroupId != null) _buildQuickActions(isDark),

          const SizedBox(height: 8),

          // ── Filter bar ──────────────────────────────────────────────────────
          if (_selectedGroupId != null)
            AttendanceFilterBar(
              selected: _provider.filterStatus,
              onSelected: _provider.setFilter,
            ),
          const SizedBox(height: 8),

          // ── List ────────────────────────────────────────────────────────────
          Expanded(
            // Issue 4: while groups are still loading, show a loading state
            // instead of flashing "No groups found" before the group context
            // resolves. The empty state now only renders once loading is done.
            // command_3: fade smoothly between loading / empty / filtered list.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey('att:$_loadingGroups:$_selectedGroupId:'
                    '${_provider.isLoading}:${_provider.error != null}:'
                    '${_provider.filterStatus}:'
                    '${_provider.filteredRecords.length}:'
                    '${_provider.guests.length}'),
                child: _loadingGroups
                ? const AppTableSkeleton(rows: 7)
                : _selectedGroupId == null
                ? const AppEmptyState(
                    icon: Icons.group_outlined,
                    title: 'No groups found',
                    subtitle: 'Create a group first to view attendance.',
                  )
                : _provider.isLoading
                    ? const AppTableSkeleton(rows: 7)
                    : _provider.error != null
                        ? AppEmptyState(
                            icon: Icons.error_outline_rounded,
                            title: 'Something went wrong',
                            subtitle: _provider.error,
                          )
                        : _provider.filteredRecords.isEmpty &&
                                _provider.guests.isEmpty
                            ? const AppEmptyState(
                                icon: Icons.assignment_outlined,
                                title: 'No records found',
                                subtitle:
                                    'No attendance records match the current filter.',
                              )
                            : ListView(
                                children: [
                                  for (var i = 0;
                                      i < _provider.filteredRecords.length;
                                      i++) ...[
                                    if (i > 0)
                                      const Divider(
                                          height: 1,
                                          indent: 56,
                                          endIndent: 16),
                                    MemberAttendanceRow(
                                      record: _provider.filteredRecords[i],
                                      onTap: () => _showOwnershipInfo(
                                          _provider.filteredRecords[i]),
                                    ),
                                  ],
                                  // Live-Test-5 (Guest Attendance Visibility
                                  // policy): hosted guests are part of the
                                  // day's attendance — a dedicated section
                                  // BELOW the member list, never merged in.
                                  // Live-Test-10: guests now FOLLOW the
                                  // active filter (Present→approved,
                                  // Absent→cancelled/no-show, Pending→
                                  // awaiting approval, Skipped/Vacation→
                                  // none) instead of always showing all.
                                  if (_provider.visibleGuests.isNotEmpty)
                                    _HostedGuestsSection(
                                      guests: _provider.visibleGuests,
                                      title: _provider.filterStatus ==
                                              AttendanceStatus.pending
                                          ? 'Guest Approval Pending'
                                          : 'Hosted Guests',
                                      onManage: _openGuests,
                                    ),
                                ],
                              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick action pill ────────────────────────────────────────────────────────

class _QuickActionPill extends StatelessWidget {
  const _QuickActionPill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.18 : 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: AppTypography.labelMedium
                      .copyWith(color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hosted guests section ────────────────────────────────────────────────────
// Live-Test-5 (Guest Attendance Visibility policy): guests are attendance
// records and render directly on the Attendance screen — a dedicated section
// below the member list (never merged into it; guests are not members). Each
// row shows guest name, host, meal, type, preference and status; tapping the
// header's manage action opens the full management sheet.

class _HostedGuestsSection extends StatelessWidget {
  const _HostedGuestsSection({
    required this.guests,
    required this.onManage,
    this.title = 'Hosted Guests',
  });

  final List<MealGuestModel> guests;
  final VoidCallback onManage;

  /// Live-Test-10: the Pending filter renders this section as a clearly
  /// separated "Guest Approval Pending" block (survey-locked wording).
  final String title;

  Color _statusColor(MealGuestModel g) {
    if (g.isCancelled) return AppColors.absent;
    if (g.isPending) return AppColors.warning;
    return AppColors.present;
  }

  String _statusLabel(MealGuestModel g) {
    if (g.isCancelled) return 'Cancelled';
    if (g.isPending) return 'Pending';
    if (g.status == 'no_show') return 'No-show';
    return 'Present';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.pagePaddingH),
          child: Row(
            children: [
              const Icon(Icons.group_add_rounded,
                  size: 18, color: AppColors.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$title (${guests.length})',
                    style: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
              TextButton(onPressed: onManage, child: const Text('Manage')),
            ],
          ),
        ),
        for (final g in guests)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.pagePaddingH, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      AppColors.secondary.withValues(alpha: 0.12),
                  child: const Icon(Icons.person_outline_rounded,
                      size: 16, color: AppColors.secondary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${(g.displayName?.isNotEmpty ?? false) ? g.displayName! : 'Guest'} · ${g.typeLabel}',
                        style: AppTypography.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (g.hostName != null) 'Host: ${g.hostName}',
                          if (g.mealName != null) g.mealName!,
                          // Live-Test-9 ISSUE-4: flat tag is the DERIVED
                          // primary (first group's pick) — only shown when
                          // there are no group picks, else it duplicated the
                          // first option ("Roti · Roti · Milk").
                          if (g.preferencesLabel.isNotEmpty)
                            g.preferencesLabel
                          else if (g.mealPreference != null &&
                              g.mealPreference!.isNotEmpty)
                            g.mealPreference!,
                        ].join(' · '),
                        style: AppTypography.labelSmall.copyWith(
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(g).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(g),
                    style: AppTypography.labelSmall.copyWith(
                        color: _statusColor(g),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Group selector bar ──────────────────────────────────────────────────────────

class _GroupSelectorBar extends StatelessWidget {
  const _GroupSelectorBar({
    required this.groups,
    required this.selectedGroupId,
    required this.onChanged,
  });

  final List<GroupModel> groups;
  final String? selectedGroupId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      color: isDark ? AppColors.surfaceDark : AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.pagePaddingH,
        vertical: 10,
      ),
      child: Row(
        children: [
          const Icon(Icons.group_outlined, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isDense: true,
                value: selectedGroupId,
                isExpanded: true,
                style: AppTypography.bodyMedium.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
                items: groups.map((g) {
                  return DropdownMenuItem(
                    value: g.id,
                    child: Text(
                      g.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat badge ─────────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                count.toString(),
                style: AppTypography.titleSmall
                    .copyWith(color: color, fontWeight: FontWeight.w800, height: 1.0),
              ),
              Text(
                label,
                style: AppTypography.labelSmall
                    .copyWith(color: color.withValues(alpha: 0.9)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// SRS Module 03 ATT-004: the admin attendance-override sheet was REMOVED —
// members own their attendance; changes flow through Correction Requests.

// ── Issue 5: admin self-attendance sheet ────────────────────────────────────

/// Lets an admin / manager mark THEIR OWN attendance for today's meals. Uses the
/// admin override endpoint with the admin's own userId, so it works even outside
/// the attendance window and snapshots the effective price (admins participate as
/// group members like anyone else).
class _MyAttendanceSheet extends StatefulWidget {
  const _MyAttendanceSheet({
    required this.organizationId,
    required this.groupId,
    required this.userId,
    required this.userName,
  });

  final String organizationId;
  final String groupId;
  final String userId;
  final String userName;

  @override
  State<_MyAttendanceSheet> createState() => _MyAttendanceSheetState();
}

class _MyAttendanceSheetState extends State<_MyAttendanceSheet> {
  final _mealRepo = MealRepository();
  final _attendanceRepo = AttendanceRepository();

  bool _loading = true;
  List<MealModel> _meals = [];
  // Live-Test-11 ISSUE-010: baseline for org-clock window gating (same
  // device-elapsed advance the student provider uses) + per-meal correction
  // mode (same-day, closed-window, no approval — the admin is the approver).
  DateTime? _fetchedAt;
  final Set<String> _correcting = {};
  final Map<String, AttendanceStatus> _status = {};
  // Issue 1/2 parity: track each meal's chosen preference like the student
  // flow, seeded from any existing record so the admin sees what they picked.
  final Map<String, String?> _selectedPref = {};
  // Live-Test-6 ISSUE-2: per-meal preference-GROUP picks (mirrors the member
  // Present gate — Present stays disabled until required groups are chosen;
  // previously this sheet sent no selections and the server 422'd).
  final Map<String, List<PreferenceSelection>> _selections = {};
  final Map<String, bool> _selectionsComplete = {};
  String? _savingMealId;
  // Issue 2: which action is in flight, so only the tapped button animates.
  AttendanceStatus? _savingStatus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _mealRepo.getTodayMeals(
          organizationId: widget.organizationId, groupId: widget.groupId),
      _attendanceRepo.getTodayAttendance(
          userId: widget.userId,
          groupId: widget.groupId,
          organizationId: widget.organizationId),
    ]);
    if (!mounted) return;
    var meals = <MealModel>[];
    if (results[0] case Ok(:final value)) meals = value as List<MealModel>;
    if (results[1] case Ok(:final value)) {
      for (final r in value as List<AttendanceModel>) {
        // GET /attendance/today is role-scoped: for an admin it returns
        // GROUP-WIDE records. This is the admin's OWN "Mark My Attendance"
        // sheet, so ignore everyone else's records — only reflect the admin's.
        if (r.userId != widget.userId) continue;
        _status[r.mealId] = r.status;
        if (r.preference != null) _selectedPref[r.mealId] = r.preference;
      }
    }
    meals.sort(MealModel.compareChronological);
    setState(() {
      _meals = meals;
      _fetchedAt = DateTime.now();
      _loading = false;
    });
  }

  /// ISSUE-010: canonical window state for [meal] — the SAME org-clock math
  /// the student surfaces use (server org-clock advanced by device-elapsed
  /// time; phone-clock fallback). 'open' includes the grace period.
  String _windowStateOf(MealModel meal) {
    final w = meal.attendanceWindow;
    if (w.openTime == '00:00' && w.closeTime == '23:59') return 'open';
    int minutesOf(String t) {
      final p = t.split(':');
      if (p.length < 2) return 0;
      return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    }

    final open = minutesOf(w.openTime);
    final close = minutesOf(w.closeTime);
    int now;
    final base = meal.orgClockMinutes;
    final at = _fetchedAt;
    if (base != null && at != null) {
      final elapsed = DateTime.now().difference(at).inMinutes;
      now = (elapsed >= 0 && elapsed <= 12 * 60)
          ? (base + elapsed) % (24 * 60)
          : TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    } else {
      final t = TimeOfDay.now();
      now = t.hour * 60 + t.minute;
    }
    final grace = meal.graceMinutes ?? 0;
    if (now < open) return 'upcoming';
    if (now < close + grace) return 'open';
    return 'closed';
  }

  Future<void> _mark(MealModel meal, AttendanceStatus status,
      {String? preference,
      List<PreferenceSelection>? selections,
      bool correction = false}) async {
    if (_savingMealId != null) return;
    setState(() {
      _savingMealId = meal.id;
      _savingStatus = status;
    });
    final now = DateTime.now();
    // Use the meal's ORG business date, not the device date (a wrong/ahead
    // phone clock would otherwise block the admin from marking). ATT-004: this
    // is the admin's OWN attendance — the server delegates self-marks to the
    // normal member path, so window rules apply like any member.
    final orgDate = meal.orgDate;
    final markDate = (orgDate != null && orgDate.length >= 10)
        ? (DateTime.tryParse(orgDate) ?? DateTime(now.year, now.month, now.day))
        : DateTime(now.year, now.month, now.day);
    final record = AttendanceModel(
      id: '',
      mealId: meal.id,
      userId: widget.userId,
      groupId: widget.groupId,
      organizationId: widget.organizationId,
      status: status,
      date: markDate,
      preference: preference,
      // ISSUE-2: group selections travel exactly like the member mark path.
      selections: selections,
    );
    final res = await _attendanceRepo.adminOverride(
        record: record, correction: correction);
    if (!mounted) return;
    setState(() {
      _savingMealId = null;
      _savingStatus = null;
    });
    switch (res) {
      case Ok(:final value):
        setState(() {
          _status[meal.id] = value.status;
          _correcting.remove(meal.id);
          if (value.preference != null) {
            _selectedPref[meal.id] = value.preference;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(correction
              ? '${meal.name}: corrected to ${status.name}'
              : '${meal.name}: marked ${status.name}'),
          duration: const Duration(seconds: 2),
        ));
      case Err(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(failure.message),
          duration: const Duration(seconds: 2),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('My attendance · today',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(widget.userName,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textTertiary)),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const AppListSkeleton(
                      rows: 3, rowHeight: 120, padding: EdgeInsets.zero)
                  : _meals.isEmpty
                      ? Center(
                          child: Text('No meals configured for today.',
                              style: AppTypography.bodyMedium
                                  .copyWith(color: AppColors.textTertiary)))
                      : ListView.separated(
                          controller: scrollCtrl,
                          itemCount: _meals.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            final meal = _meals[i];
                            final st =
                                _status[meal.id] ?? AttendanceStatus.pending;
                            return _MySelfMealCard(
                              meal: meal,
                              status: st,
                              // ISSUE-010: member-rule parity — buttons hide
                              // outside the window; closed offers same-day
                              // correction (no approval).
                              windowState: _windowStateOf(meal),
                              correcting: _correcting.contains(meal.id),
                              onStartCorrection: () => setState(
                                  () => _correcting.add(meal.id)),
                              selectedPref: _selectedPref[meal.id],
                              // ISSUE-2: required-group completeness gates
                              // Present exactly like the student card — the
                              // shared no-picks rule (respects visibleWhen +
                              // the fail-safe), refined live by the selector.
                              selectionsComplete: _selectionsComplete[
                                      meal.id] ??
                                  PreferenceGroupSelector.initialComplete(
                                      meal.preferenceGroups),
                              savingStatus: _savingMealId == meal.id
                                  ? _savingStatus
                                  : null,
                              busy: _savingMealId != null,
                              onSelectPref: (opt) => setState(() {
                                _selectedPref[meal.id] =
                                    _selectedPref[meal.id] == opt ? null : opt;
                              }),
                              onSelectionsChanged:
                                  (selections, delta, complete) => setState(() {
                                _selections[meal.id] = selections;
                                _selectionsComplete[meal.id] = complete;
                              }),
                              onMark: (newStatus, pref) => _mark(
                                meal,
                                newStatus,
                                preference: pref,
                                selections:
                                    newStatus == AttendanceStatus.present &&
                                            meal.preferenceGroups.isNotEmpty
                                        ? (_selections[meal.id] ?? const [])
                                        : null,
                                correction: _correcting.contains(meal.id),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MySelfMealCard extends StatelessWidget {
  const _MySelfMealCard({
    required this.meal,
    required this.status,
    required this.selectedPref,
    required this.savingStatus,
    required this.busy,
    required this.onSelectPref,
    required this.onMark,
    this.selectionsComplete = true,
    this.onSelectionsChanged,
    this.windowState = 'open',
    this.correcting = false,
    this.onStartCorrection,
  });

  final MealModel meal;
  final AttendanceStatus status;
  final String? selectedPref;

  /// ISSUE-010: 'upcoming' | 'open' (incl. grace) | 'closed' — member parity.
  final String windowState;

  /// ISSUE-010: closed-window same-day correction mode is active for this meal.
  final bool correcting;
  final VoidCallback? onStartCorrection;
  // Non-null when THIS meal has an action saving — the specific action in
  // flight, so only that button animates.
  final AttendanceStatus? savingStatus;
  // True when any action across the sheet is saving (disable others).
  final bool busy;
  final void Function(String option) onSelectPref;
  final void Function(AttendanceStatus status, String? preference) onMark;

  /// ISSUE-2: preference-GROUP completeness (Present gate) + change sink.
  final bool selectionsComplete;
  final void Function(
          List<PreferenceSelection> selections, int delta, bool complete)?
      onSelectionsChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefsOn =
        meal.preferencesEnabled && meal.enabledPreferences.isNotEmpty;
    final groupsOn = meal.preferenceGroups.isNotEmpty;
    final canPresent =
        (!prefsOn || selectedPref != null) && (!groupsOn || selectionsComplete);
    final menu = meal.menuItems.where((e) => e.trim().isNotEmpty).toList();
    // ISSUE-010 member parity: actions render only while the window is open
    // (incl. grace) — or in explicit same-day correction mode after close.
    final actionable = windowState == 'open' || correcting;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(meal.name,
                    style: AppTypography.labelLarge
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
              if (status != AttendanceStatus.pending)
                _SelfStatusPill(status: status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              'Window  ${TimeFormat.window12(meal.attendanceWindow.openTime, meal.attendanceWindow.closeTime)}',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary)),
          // Menu details (Issue 2: parity with what students can see).
          if (menu.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(menu.join(', '),
                style: AppTypography.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                )),
          ],
          // Preference chips (Issue 1/2 parity with the student flow).
          if (prefsOn && actionable) ...[
            const SizedBox(height: 12),
            Text('Meal preference (required)',
                style: AppTypography.labelSmall.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                )),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              // ISSUE-008: the system "None" choice is always offered last.
              children: [
                ...meal.enabledPreferences,
                if (!meal.enabledPreferences.any((p) =>
                    p.trim().toLowerCase() == MealPreferenceOption.noneKey))
                  MealPreferenceOption.noneKey,
              ].map((opt) {
                final isSelected = selectedPref == opt;
                final disp = MealPreferenceOption.display(opt);
                return GestureDetector(
                  onTap: busy ? null : () => onSelectPref(opt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : isDark
                              ? AppColors.surfaceVariantDark
                              : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                    ? AppColors.borderDark
                                    : AppColors.border)
                                .withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(disp.emoji,
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 5),
                        Text(disp.label,
                            style: AppTypography.labelSmall.copyWith(
                              color: isSelected
                                  ? Colors.white
                                  : isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          // ISSUE-2: multi-preference groups — the SAME selector the student
          // attendance card uses, so admin self-marks satisfy required groups
          // instead of 422-ing at the server.
          if (groupsOn && actionable) ...[
            const SizedBox(height: 12),
            PreferenceGroupSelector(
              groups: meal.preferenceGroups,
              enabled: !busy,
              onChanged: (selections, delta, complete) =>
                  onSelectionsChanged?.call(selections, delta, complete),
            ),
          ],
          const SizedBox(height: 12),
          // ISSUE-010: EXACT member-rule parity.
          //   upcoming → no actions, window not open yet.
          //   open/grace (or correction mode) → Present/Absent, preference-gated.
          //   closed → buttons hidden; same-day correction entry instead.
          if (actionable)
            Row(
              children: [
                _SelfBtn(
                  label: 'Present',
                  selected: status == AttendanceStatus.present,
                  color: AppColors.present,
                  loading: savingStatus == AttendanceStatus.present,
                  enabled: canPresent && !busy,
                  onTap: () => onMark(
                      AttendanceStatus.present, prefsOn ? selectedPref : null),
                ),
                const SizedBox(width: 8),
                // Q17/Q21: Skip button removed — Present or Absent only.
                _SelfBtn(
                  label: 'Absent',
                  selected: status == AttendanceStatus.absent,
                  color: AppColors.absent,
                  loading: savingStatus == AttendanceStatus.absent,
                  enabled: !busy,
                  onTap: () => onMark(AttendanceStatus.absent, null),
                ),
              ],
            )
          else if (windowState == 'upcoming')
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 14,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textTertiary),
                const SizedBox(width: 6),
                Text(
                  'Window not open yet',
                  style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Icon(Icons.lock_clock_rounded,
                    size: 14,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textTertiary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Attendance window closed',
                    style: AppTypography.bodySmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
            if (onStartCorrection != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onStartCorrection,
                  icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                  label: const Text('Correct attendance'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    textStyle: AppTypography.labelMedium
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SelfStatusPill extends StatelessWidget {
  const _SelfStatusPill({required this.status});
  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    Color c;
    String label;
    switch (status) {
      case AttendanceStatus.present:
        c = AppColors.present;
        label = 'Present';
      case AttendanceStatus.absent:
        c = AppColors.absent;
        label = 'Absent';
      case AttendanceStatus.skipped:
        c = AppColors.skipped;
        label = 'Skipped';
      case AttendanceStatus.onVacation:
        c = AppColors.vacation;
        label = 'Vacation';
      case AttendanceStatus.pending:
        c = AppColors.warning;
        label = 'Pending';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: AppTypography.labelSmall
              .copyWith(color: c, fontWeight: FontWeight.w700)),
    );
  }
}

class _SelfBtn extends StatelessWidget {
  const _SelfBtn({
    required this.label,
    required this.selected,
    required this.color,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = enabled && !loading;
    return Expanded(
      child: InkWell(
        onTap: active ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected
                    ? color
                    : AppColors.border.withValues(alpha: 0.6)),
          ),
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label,
                  style: AppTypography.labelMedium.copyWith(
                    color: selected
                        ? color
                        : (enabled
                            ? AppColors.textSecondary
                            : AppColors.textSecondary.withValues(alpha: 0.4)),
                    fontWeight: FontWeight.w700,
                  )),
        ),
      ),
    );
  }
}

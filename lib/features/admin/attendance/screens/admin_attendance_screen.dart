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
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

/// Admin screen for viewing group attendance on a specific date.
///
/// Includes a group selector so admins managing multiple groups can switch
/// context without leaving the screen.
class AdminAttendanceScreen extends StatefulWidget {
  const AdminAttendanceScreen({super.key});

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
      case Err():
        setState(() => _loadingGroups = false);
    }
  }

  Future<void> _loadAttendance(String orgId) async {
    if (_selectedGroupId == null) return;
    await _provider.load(
      groupId: _selectedGroupId!,
      organizationId: orgId,
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
                    '${_provider.filteredRecords.length}'),
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
                        : _provider.filteredRecords.isEmpty
                            ? const AppEmptyState(
                                icon: Icons.assignment_outlined,
                                title: 'No records found',
                                subtitle:
                                    'No attendance records match the current filter.',
                              )
                            : ListView.separated(
                                itemCount: _provider.filteredRecords.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  indent: 56,
                                  endIndent: 16,
                                ),
                                itemBuilder: (context, i) {
                                  final record = _provider.filteredRecords[i];
                                  return MemberAttendanceRow(
                                    record: record,
                                    onTap: () => _showOwnershipInfo(record),
                                  );
                                },
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
  final Map<String, AttendanceStatus> _status = {};
  // Issue 1/2 parity: track each meal's chosen preference like the student
  // flow, seeded from any existing record so the admin sees what they picked.
  final Map<String, String?> _selectedPref = {};
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
      _loading = false;
    });
  }

  Future<void> _mark(MealModel meal, AttendanceStatus status,
      {String? preference}) async {
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
    );
    final res = await _attendanceRepo.adminOverride(record: record);
    if (!mounted) return;
    setState(() {
      _savingMealId = null;
      _savingStatus = null;
    });
    switch (res) {
      case Ok(:final value):
        setState(() {
          _status[meal.id] = value.status;
          if (value.preference != null) {
            _selectedPref[meal.id] = value.preference;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${meal.name}: marked ${status.name}'),
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
                              selectedPref: _selectedPref[meal.id],
                              savingStatus: _savingMealId == meal.id
                                  ? _savingStatus
                                  : null,
                              busy: _savingMealId != null,
                              onSelectPref: (opt) => setState(() {
                                _selectedPref[meal.id] =
                                    _selectedPref[meal.id] == opt ? null : opt;
                              }),
                              onMark: (newStatus, pref) =>
                                  _mark(meal, newStatus, preference: pref),
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
  });

  final MealModel meal;
  final AttendanceStatus status;
  final String? selectedPref;
  // Non-null when THIS meal has an action saving — the specific action in
  // flight, so only that button animates.
  final AttendanceStatus? savingStatus;
  // True when any action across the sheet is saving (disable others).
  final bool busy;
  final void Function(String option) onSelectPref;
  final void Function(AttendanceStatus status, String? preference) onMark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prefsOn =
        meal.preferencesEnabled && meal.enabledPreferences.isNotEmpty;
    final canPresent = !prefsOn || selectedPref != null;
    final menu = meal.menuItems.where((e) => e.trim().isNotEmpty).toList();

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
          if (prefsOn) ...[
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
              children: meal.enabledPreferences.map((opt) {
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
          const SizedBox(height: 12),
          Row(
            children: [
              _SelfBtn(
                label: 'Present',
                selected: status == AttendanceStatus.present,
                color: AppColors.present,
                loading: savingStatus == AttendanceStatus.present,
                enabled: canPresent && !busy,
                onTap: () =>
                    onMark(AttendanceStatus.present, prefsOn ? selectedPref : null),
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
          ),
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

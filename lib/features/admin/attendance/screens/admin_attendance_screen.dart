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
import 'package:smart_meal_management/features/admin/attendance/widgets/attendance_filter_bar.dart';
import 'package:smart_meal_management/features/admin/attendance/widgets/member_attendance_row.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/shared/widgets/app_loading_indicator.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

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
      final cached = await ResponseCacheService.instance.readList(
          'admin_groups:$orgId', GroupModel.fromJson,
          maxAge: const Duration(hours: 12));
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _groups = cached;
          _selectedGroupId = resolveSelected(cached);
        });
        if (_selectedGroupId != null) await _loadAttendance(orgId);
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

  /// Shows the admin attendance override bottom sheet for a single record.
  ///
  /// Admin can change any member's status regardless of timing windows.
  Future<void> _showOverrideSheet(AttendanceModel record) async {
    final selected = await showModalBottomSheet<AttendanceStatus>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AttendanceOverrideSheet(record: record),
    );
    if (selected == null || !mounted) return;
    final ok = await _provider.markAttendance(
      recordId: record.id,
      newStatus: selected,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Attendance updated to ${selected.name}'
            : 'Failed to update attendance'),
        duration: const Duration(seconds: 2),
      ),
    );
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
        actions: [
          // Issue 3: admin reviews member vacation requests (approve/reject/cancel).
          IconButton(
            tooltip: 'Vacation requests',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const VacationRequestsScreen()),
            ),
            icon: const Icon(Icons.beach_access_rounded, size: 20),
          ),
          // Module 33 (ISSUE-17): post-window correction requests queue —
          // approve applies + bills; reject changes nothing.
          IconButton(
            tooltip: 'Correction requests',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const CorrectionRequestsScreen()),
            ),
            icon: const Icon(Icons.rule_rounded, size: 20),
          ),
          // Issue 5: an admin / manager can mark THEIR OWN attendance for today.
          if (_selectedGroupId != null)
            IconButton(
              tooltip: 'Mark my attendance',
              onPressed: _openMyAttendance,
              icon: const Icon(Icons.how_to_reg_rounded, size: 20),
            ),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today_rounded, size: 16),
            label: Text(dateStr, style: AppTypography.labelMedium),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // ── Group selector ──────────────────────────────────────────────────
          if (_loadingGroups)
            const LinearProgressIndicator()
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
                        color: AppColors.present),
                    const SizedBox(width: 12),
                    _StatBadge(
                        label: 'Absent',
                        count: _provider.absentCount,
                        color: AppColors.absent),
                    const SizedBox(width: 12),
                    _StatBadge(
                        label: 'Pending',
                        count: _provider.pendingCount,
                        color: AppColors.warning),
                    const SizedBox(width: 12),
                    // Issue 4: vacation members tracked separately — they are
                    // NOT counted as present / absent / pending.
                    _StatBadge(
                        label: 'Vacation',
                        count: _provider.vacationCount,
                        color: AppColors.vacation),
                  ],
                ),
              ),
            ),
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
            child: _loadingGroups
                ? const AppLoadingIndicator()
                : _selectedGroupId == null
                ? const AppEmptyState(
                    icon: Icons.group_outlined,
                    title: 'No groups found',
                    subtitle: 'Create a group first to view attendance.',
                  )
                : _provider.isLoading
                    ? const AppLoadingIndicator()
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
                                    onTap: () => _showOverrideSheet(record),
                                  );
                                },
                              ),
          ),
        ],
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
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: AppTypography.numericSmall.copyWith(color: color),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// ── Attendance override bottom sheet ───────────────────────────────────────────

/// Admin override bottom sheet — lets admin set any attendance status for a
/// member, bypassing the normal timing window restriction.
class _AttendanceOverrideSheet extends StatelessWidget {
  const _AttendanceOverrideSheet({required this.record});
  final AttendanceModel record;

  static const _options = [
    (AttendanceStatus.present, 'Mark Present', Icons.check_circle_rounded, AppColors.present),
    (AttendanceStatus.absent,  'Mark Absent',  Icons.cancel_rounded,       AppColors.absent),
    (AttendanceStatus.skipped, 'Mark Skipped', Icons.remove_circle_outline_rounded, AppColors.skipped),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = record.mealName ?? record.mealId;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.borderDark : AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Override Attendance',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Member · $name',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Admin override — ignores attendance window',
              style: AppTypography.labelSmall.copyWith(color: AppColors.warning),
            ),
          ),
          const SizedBox(height: 20),
          ..._options.map((opt) {
            final (status, label, icon, color) = opt;
            final isCurrent = record.status == status;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: isCurrent
                    ? color.withValues(alpha: 0.08)
                    : (isDark ? AppColors.backgroundDark : AppColors.background),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.pop(context, status),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Icon(icon, color: color, size: 22),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(label,
                              style: AppTypography.bodyMedium.copyWith(
                                color: isCurrent ? color : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
                                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                              )),
                        ),
                        if (isCurrent)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Current',
                                style: AppTypography.labelSmall.copyWith(color: color)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


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
    final record = AttendanceModel(
      id: '',
      mealId: meal.id,
      userId: widget.userId,
      groupId: widget.groupId,
      organizationId: widget.organizationId,
      status: status,
      date: DateTime(now.year, now.month, now.day),
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
                  ? const Center(child: CircularProgressIndicator())
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
              _SelfBtn(
                label: 'Skip',
                selected: status == AttendanceStatus.skipped,
                color: AppColors.warning,
                loading: savingStatus == AttendanceStatus.skipped,
                enabled: !busy,
                onTap: () => onMark(AttendanceStatus.skipped, null),
              ),
              const SizedBox(width: 8),
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

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/attendance_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/features/admin/attendance/providers/admin_attendance_provider.dart';
import 'package:smart_meal_management/features/admin/attendance/widgets/attendance_filter_bar.dart';
import 'package:smart_meal_management/features/admin/attendance/widgets/member_attendance_row.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
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
    setState(() => _loadingGroups = true);
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) {
      setState(() => _loadingGroups = false);
      return;
    }
    final orgId = user.organizationId;

    final result = await _groupRepo.getOrganisationGroups(
      organizationId: orgId,
    );

    if (!mounted) return;

    switch (result) {
      case Ok(:final value):
        final groups = value.data;
        setState(() {
          _groups = groups;
          _loadingGroups = false;
          // Default to the user's first effective group, falling back to the
          // first group in the list. Uses effectiveGroupIds.firstOrNull for
          // multi-group correctness (consistent with all other screens).
          final userGroupId = auth.currentUser?.effectiveGroupIds.firstOrNull;
          final match = groups.any((g) => g.id == userGroupId);
          _selectedGroupId = match
              ? userGroupId
              : (groups.isNotEmpty ? groups.first.id : null);
        });
        if (_selectedGroupId != null) {
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
                ],
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
            child: _selectedGroupId == null
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
  String? _savingMealId;

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
        _status[r.mealId] = r.status;
      }
    }
    meals.sort((a, b) => a.order.compareTo(b.order));
    setState(() {
      _meals = meals;
      _loading = false;
    });
  }

  Future<void> _mark(MealModel meal, AttendanceStatus status) async {
    setState(() => _savingMealId = meal.id);
    final now = DateTime.now();
    final record = AttendanceModel(
      id: '',
      mealId: meal.id,
      userId: widget.userId,
      groupId: widget.groupId,
      organizationId: widget.organizationId,
      status: status,
      date: DateTime(now.year, now.month, now.day),
    );
    final res = await _attendanceRepo.adminOverride(record: record);
    if (!mounted) return;
    setState(() => _savingMealId = null);
    switch (res) {
      case Ok(:final value):
        setState(() => _status[meal.id] = value.status);
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
                              saving: _savingMealId == meal.id,
                              onMark: (newStatus) => _mark(meal, newStatus),
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
    required this.saving,
    required this.onMark,
  });

  final MealModel meal;
  final AttendanceStatus status;
  final bool saving;
  final void Function(AttendanceStatus) onMark;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
              Text(
                  '${meal.attendanceWindow.openTime}–${meal.attendanceWindow.closeTime}',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 10),
          if (saving)
            const SizedBox(
              height: 38,
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            Row(
              children: [
                _SelfBtn(
                    label: 'Present',
                    selected: status == AttendanceStatus.present,
                    color: AppColors.present,
                    onTap: () => onMark(AttendanceStatus.present)),
                const SizedBox(width: 8),
                _SelfBtn(
                    label: 'Skip',
                    selected: status == AttendanceStatus.skipped,
                    color: AppColors.warning,
                    onTap: () => onMark(AttendanceStatus.skipped)),
                const SizedBox(width: 8),
                _SelfBtn(
                    label: 'Absent',
                    selected: status == AttendanceStatus.absent,
                    color: AppColors.absent,
                    onTap: () => onMark(AttendanceStatus.absent)),
              ],
            ),
        ],
      ),
    );
  }
}

class _SelfBtn extends StatelessWidget {
  const _SelfBtn({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
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
          child: Text(label,
              style: AppTypography.labelMedium.copyWith(
                color: selected ? color : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              )),
        ),
      ),
    );
  }
}

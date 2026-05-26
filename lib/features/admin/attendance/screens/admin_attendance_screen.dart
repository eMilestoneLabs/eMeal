import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
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

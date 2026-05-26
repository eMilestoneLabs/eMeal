import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/groups/providers/admin_group_provider.dart';
import 'package:smart_meal_management/features/admin/groups/widgets/group_card.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/shared/widgets/app_loading_indicator.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Admin groups list screen.
///
/// Lists all groups for the admin's organisation. The FAB opens a creation
/// bottom sheet — never navigates to a non-existent `:groupId` route.
class AdminGroupsScreen extends StatefulWidget {
  const AdminGroupsScreen({super.key});

  @override
  State<AdminGroupsScreen> createState() => _AdminGroupsScreenState();
}

class _AdminGroupsScreenState extends State<AdminGroupsScreen> {
  late final AdminGroupProvider _provider;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _provider = AdminGroupProvider();
      _provider.addListener(_rebuild);
      final auth = AuthProviderScope.of(context);
      final user = auth.currentUser;
      if (user == null) return;
      _provider.loadGroups(
        organizationId: user.organizationId,
      );
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  /// Shows the create-group bottom sheet.
  ///
  /// On success, navigates straight to the new group's detail screen.
  Future<void> _showCreateSheet() async {
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    final orgId = user.organizationId;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateGroupSheet(
        provider: _provider,
        organizationId: orgId,
        onCreated: (group) {
          if (!mounted) return;
          context.push(
            RouteNames.adminGroupDetail.replaceAll(':groupId', group.id),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Groups', style: AppTypography.titleLarge),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Group'),
      ),
      body: _provider.isLoading
          ? const AppLoadingIndicator()
          : _provider.error != null
              ? AppEmptyState(
                  icon: Icons.error_outline_rounded,
                  title: 'Could not load groups',
                  subtitle: _provider.error,
                  action: TextButton(
                    onPressed: () {
                      final user = AuthProviderScope.of(context).currentUser;
                      if (user == null) return;
                      _provider.loadGroups(
                        organizationId: user.organizationId,
                      );
                    },
                    child: const Text('Retry'),
                  ),
                )
              : _provider.groups.isEmpty
                  ? AppEmptyState(
                      icon: Icons.group_outlined,
                      title: 'No groups yet',
                      subtitle: 'Create your first group to get started.',
                      action: FilledButton.icon(
                        onPressed: _showCreateSheet,
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create Group'),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        final user = AuthProviderScope.of(context).currentUser;
                        if (user == null) return;
                        await _provider.loadGroups(
                          organizationId: user.organizationId,
                        );
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: _provider.groups.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final group = _provider.groups[i];
                          return GroupCard(
                            group: group,
                            onTap: () => context.push(
                              RouteNames.adminGroupDetail
                                  .replaceAll(':groupId', group.id),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

// ── Create Group Bottom Sheet ──────────────────────────────────────────────────

/// Modal bottom sheet for creating a new group.
///
/// Collects name + type, calls [AdminGroupProvider.createGroup], then invokes
/// [onCreated] so the parent can navigate to the freshly created group.
class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({
    required this.provider,
    required this.organizationId,
    required this.onCreated,
  });

  final AdminGroupProvider provider;
  final String organizationId;
  final void Function(GroupModel group) onCreated;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  GroupType _type = GroupType.hostel;
  bool _mealsEnabled = true;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);

    final group = await widget.provider.createGroup(
      organizationId: widget.organizationId,
      name: name,
      type: _type,
      mealConfig: GroupMealConfig(mealsEnabled: _mealsEnabled),
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (group != null) {
      Navigator.of(context).pop();
      widget.onCreated(group);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.provider.error ?? 'Failed to create group'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Create New Group',
            style: AppTypography.titleMedium
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Set up a hostel, mess, cafeteria or any group.',
            style: AppTypography.bodySmall
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),

          // ── Group Name ─────────────────────────────────────────────────
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Group Name *',
              hintText: 'e.g. Hostel Block A, Office Cafeteria',
              filled: true,
              fillColor: colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Group Type ─────────────────────────────────────────────────
          Text(
            'Group Type',
            style: AppTypography.labelMedium
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _TypeGrid(
            selected: _type,
            onSelected: (t) => setState(() => _type = t),
          ),
          const SizedBox(height: 16),

          // ── Meals toggle ───────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            ),
            child: SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              title: Text(
                'Enable Meal System',
                style: AppTypography.labelMedium
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _mealsEnabled
                    ? 'Students can view menus and mark meal attendance.'
                    : 'Attendance only — no meal features.',
                style: AppTypography.bodySmall
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
              value: _mealsEnabled,
              onChanged: (v) => setState(() => _mealsEnabled = v),
            ),
          ),
          const SizedBox(height: 24),

          // ── Save ───────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _saving || _nameCtrl.text.trim().isEmpty
                  ? null
                  : _save,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Group',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Group type grid ────────────────────────────────────────────────────────────

class _TypeGrid extends StatelessWidget {
  const _TypeGrid({required this.selected, required this.onSelected});

  final GroupType selected;
  final ValueChanged<GroupType> onSelected;

  static const _types = [
    (GroupType.hostel,          'Hostel',      Icons.apartment_rounded),
    (GroupType.mess,            'Mess',        Icons.restaurant_rounded),
    (GroupType.cafeteria,       'Cafeteria',   Icons.local_cafe_rounded),
    (GroupType.pg,              'PG',          Icons.home_rounded),
    (GroupType.office,          'Office',      Icons.business_rounded),
    (GroupType.coachingInstitute,'Coaching',   Icons.school_rounded),
    (GroupType.factory_,        'Factory',     Icons.factory_rounded),
    (GroupType.community,       'Community',   Icons.people_rounded),
    (GroupType.event,           'Event',       Icons.celebration_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _types.map((entry) {
        final (type, label, icon) = entry;
        final isSelected = selected == type;
        return _TypeChip(
          label: label,
          icon: icon,
          isSelected: isSelected,
          onTap: () => onSelected(type),
        );
      }).toList(),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.10)
              : colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? AppColors.primary
                  : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppColors.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

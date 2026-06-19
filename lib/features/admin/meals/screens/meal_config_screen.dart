import 'package:flutter/material.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/features/admin/meals/providers/meal_config_provider.dart';
import 'package:smart_meal_management/features/admin/meals/widgets/meal_config_form.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/shared/widgets/app_section_title.dart';
import 'package:smart_meal_management/shared/widgets/app_status_chip.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Admin meal configuration screen.
///
/// Group selector → master meal toggle → preferences toggle → meal list.
/// If meal system is OFF, shows explanation card; attendance still works.
class MealConfigScreen extends StatefulWidget {
  const MealConfigScreen({super.key});

  @override
  State<MealConfigScreen> createState() => _MealConfigScreenState();
}

class _MealConfigScreenState extends State<MealConfigScreen> {
  late final MealConfigProvider _provider;
  bool _initialized = false;
  String _orgId = '';

  @override
  void initState() {
    super.initState();
    _provider = MealConfigProvider();
    _provider.addListener(_rebuild);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final auth = AuthProviderScope.of(context);
      final user = auth.currentUser;
      if (user == null) return;
      _orgId = user.organizationId;
      _provider.loadGroups(organizationId: _orgId);
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Meal Config'),
        centerTitle: false,
        actions: [
          if (_provider.selectedGroup != null)
            TextButton.icon(
              onPressed: () => context.push('${RouteNames.adminMealSchedule}?groupId=${_provider.selectedGroup!.id}'),
              icon: const Icon(Icons.calendar_month_rounded, size: 16),
              label: const Text('Schedule'),
            ),
        ],
      ),
      floatingActionButton: _provider.mealsEnabled &&
              _provider.selectedGroup != null
          ? FloatingActionButton.extended(
              onPressed: () => _showAddMealSheet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Meal'),
            )
          : null,
      body: _provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
              children: [
                // ── Group selector ────────────────────────────────────────
                if (_provider.groups.isNotEmpty) ...[
                  const AppSectionTitle(
                    title: 'Select Group',
                    subtitle: 'Configure meals per group',
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _provider.groups.map((g) {
                        final selected =
                            _provider.selectedGroup?.id == g.id;
                        return GestureDetector(
                          onTap: () => _provider.selectGroup(
                            g,
                            organizationId: _orgId,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary
                                  : colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : colorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              g.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color:
                                    selected ? Colors.white : null,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                if (_provider.selectedGroup == null) ...[
                  const AppEmptyState(
                    icon: Icons.group_off_rounded,
                    title: 'No groups yet',
                    subtitle: 'Create a group first.',
                  ),
                ] else ...[
                  // ── Master meal toggle ───────────────────────────────────
                  const AppSectionTitle(title: 'Meal System'),
                  const SizedBox(height: 12),
                  _ToggleTile(
                    icon: Icons.restaurant_rounded,
                    title: 'Meals Enabled',
                    subtitle: _provider.mealsEnabled
                        ? 'Members can view menus and mark meal attendance'
                        : 'Attendance-only mode — meal UI hidden from members',
                    value: _provider.mealsEnabled,
                    onChanged: _provider.isSaving
                        ? null
                        : (v) => _provider.toggleMealSystem(
                              organizationId: _orgId,
                              groupId:
                                  _provider.selectedGroup!.id,
                              enabled: v,
                            ),
                  ),
                  const SizedBox(height: 12),

                  if (_provider.mealsEnabled) ...[
                    // ── Preferences toggle ─────────────────────────────────
                    _ToggleTile(
                      icon: Icons.tune_rounded,
                      title: 'Meal Preferences',
                      subtitle: _provider.preferencesEnabled
                          ? 'Members tag Veg/Chicken/Fish etc. before attendance'
                          : 'No preference selection — just mark present/absent',
                      value: _provider.preferencesEnabled,
                      onChanged: _provider.isSaving
                          ? null
                          : (v) => _provider.togglePreferences(
                                organizationId: _orgId,
                                groupId:
                                    _provider.selectedGroup!.id,
                                enabled: v,
                              ),
                    ),
                    const SizedBox(height: 24),

                    // ── Meal list ──────────────────────────────────────────
                    AppSectionTitle(
                      title: 'Configured Meals',
                      subtitle: '${_provider.meals.length} meals',
                      actionLabel: 'Schedule →',
                      onActionTap: () =>
                          context.push('${RouteNames.adminMealSchedule}?groupId=${_provider.selectedGroup!.id}'),
                    ),
                    const SizedBox(height: 12),
                    if (_provider.meals.isEmpty)
                      const AppEmptyState(
                        icon: Icons.no_meals_rounded,
                        title: 'No meals configured',
                        subtitle:
                            'Tap + Add Meal to create your first meal.',
                      )
                    else
                      ...(_provider.meals.map(
                        (meal) => _MealTile(
                          meal: meal,
                          onEdit: () =>
                              _showEditMealSheet(context, meal),
                          onDelete: () =>
                              _confirmDelete(context, meal),
                          onToggle: (enabled) => _provider.updateMeal(
                            organizationId: _orgId,
                            groupId: meal.groupId,
                            mealId: meal.id,
                            isActive: enabled,
                          ),
                        ),
                      )),
                  ] else ...[
                    // Attendance-only explanation
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color:
                              AppColors.primary.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.how_to_reg_rounded,
                            color: AppColors.primary,
                            size: 36,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Attendance-Only Mode Active',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Meal menus and timelines are hidden. Members continue to mark daily attendance.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  void _showAddMealSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            children: [
              const Text(
                'Add Meal',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              MealConfigForm(
                isSaving: _provider.isSaving,
                // Inherit global preference state — new meals default ON
                // when the group's preference toggle is already enabled.
                initialPreferencesEnabled: _provider.preferencesEnabled,
                onSave: (data) async {
                  final group = _provider.selectedGroup;
                  if (group == null) return;
                  // Capture navigator before async gap.
                  final nav = Navigator.of(context);
                  await _provider.createMeal(
                    organizationId: _orgId,
                    groupId: group.id,
                    name: data.name,
                    slotKey: data.slotKey,
                    order: data.order,
                    description: data.description,
                    attendanceWindow: MealAttendanceWindow(
                      openTime: data.openTime,
                      closeTime: data.closeTime,
                    ),
                    menuItems: data.menuItems,
                    availablePreferences: data.enablePreferences,
                    imageBytes: data.imageBytes,
                  );
                  if (mounted) nav.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditMealSheet(BuildContext context, MealModel meal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            children: [
              const Text(
                'Edit Meal',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              MealConfigForm(
                initialMeal: meal,
                isSaving: _provider.isSaving,
                onSave: (data) async {
                  // Capture navigator before async gap.
                  final nav = Navigator.of(context);
                  await _provider.updateMeal(
                    organizationId: _orgId,
                    groupId: meal.groupId,
                    mealId: meal.id,
                    name: data.name,
                    description: data.description,
                    attendanceWindow: MealAttendanceWindow(
                      openTime: data.openTime,
                      closeTime: data.closeTime,
                    ),
                    menuItems: data.menuItems,
                    availablePreferences: data.enablePreferences,
                    imageBytes: data.imageBytes.isNotEmpty
                        ? data.imageBytes
                        : null,
                  );
                  if (mounted) nav.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, MealModel meal) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${meal.name}?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _provider.deleteMeal(
        organizationId: _orgId,
        groupId: meal.groupId,
        mealId: meal.id,
      );
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${meal.name} deleted'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ── Toggle tile ───────────────────────────────────────────────────────────────

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ── Meal tile ─────────────────────────────────────────────────────────────────

class _MealTile extends StatelessWidget {
  const _MealTile({
    required this.meal,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final MealModel meal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(meal.icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${meal.attendanceWindow.openTime}–${meal.attendanceWindow.closeTime}',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (meal.menuItems.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${meal.menuItems.length} items',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Status + menu
          AppStatusChip.label(
            label: meal.isActive ? 'On' : 'Off',
            color: meal.isActive ? AppColors.present : AppColors.textTertiary,
            compact: true,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<_MealAction>(
            icon: Icon(Icons.more_vert_rounded,
                size: 18, color: colorScheme.onSurfaceVariant),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _MealAction.toggle,
                child: Text(meal.isActive ? 'Disable' : 'Enable'),
              ),
              const PopupMenuItem(
                value: _MealAction.edit,
                child: Text('Edit'),
              ),
              const PopupMenuItem(
                value: _MealAction.delete,
                child: Text('Delete'),
              ),
            ],
            onSelected: (action) {
              switch (action) {
                case _MealAction.toggle:
                  onToggle(!meal.isActive);
                case _MealAction.edit:
                  onEdit();
                case _MealAction.delete:
                  onDelete();
              }
            },
          ),
        ],
      ),
    );
  }
}

enum _MealAction { toggle, edit, delete }

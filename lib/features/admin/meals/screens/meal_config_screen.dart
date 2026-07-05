import 'package:flutter/material.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/features/admin/meals/providers/meal_config_provider.dart';
import 'package:smart_meal_management/features/admin/meals/screens/preference_groups_screen.dart';
import 'package:smart_meal_management/features/admin/meals/widgets/guest_config_sheet.dart';
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

  /// Module 22 (FR-HG-021, Pass 9): caps / pricing / approval settings for
  /// hosted guests. The backend 422s (GUEST_PRICE_REQUIRED etc.) surface
  /// through the provider error, shown as a snackbar here.
  Future<void> _openGuestSettings() async {
    final group = _provider.selectedGroup;
    if (group == null) return;
    final edited = await showGuestConfigSheet(
      context,
      config: _provider.guestConfig,
      pricingEnabled: _provider.mealPricingEnabled,
    );
    if (edited == null || !mounted) return;
    final ok = await _provider.updateGuestConfig(
      organizationId: _orgId,
      groupId: group.id,
      config: edited,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Guest settings saved.'
            : (_provider.error ?? 'Could not save guest settings')),
        behavior: SnackBarBehavior.floating,
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Master Meal Template'),
        centerTitle: false,
        actions: [
          if (_provider.selectedGroup != null)
            Builder(builder: (context) {
              // Day-Wise Mode and Weekly Mode are mutually exclusive. When the
              // group is in Day-Wise mode the weekly planner is hidden and the
              // admin instead opens the Today/Tomorrow daily planner. Weekly
              // mode behaviour is unchanged (mode param absent).
              final dayWise =
                  _provider.selectedGroup!.mealConfig.dayWiseMealsEnabled;
              final id = _provider.selectedGroup!.id;
              return TextButton.icon(
                onPressed: () => context.push(
                  dayWise
                      ? '${RouteNames.adminMealSchedule}?groupId=$id&mode=daywise'
                      : '${RouteNames.adminMealSchedule}?groupId=$id',
                ),
                icon: Icon(
                  dayWise
                      ? Icons.today_rounded
                      : Icons.calendar_month_rounded,
                  size: 16,
                ),
                label: Text(dayWise ? 'Daily Plan' : 'Schedule'),
              );
            }),
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

                if (_provider.groups.isEmpty) ...[
                  const AppEmptyState(
                    icon: Icons.group_off_rounded,
                    title: 'No groups yet',
                    subtitle: 'Create a group first.',
                  ),
                ] else if (_provider.selectedGroup == null) ...[
                  // Groups exist but none resolved yet (brief) — show a loader,
                  // never the misleading "No groups yet" empty state.
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
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
                    const SizedBox(height: 12),

                    // ── Meal pricing toggle ────────────────────────────────
                    _ToggleTile(
                      icon: Icons.payments_rounded,
                      title: 'Enable Meal Pricing',
                      subtitle: _provider.mealPricingEnabled
                          ? 'Meals carry a ₹ price — shown to members & used for billing'
                          : 'No pricing — members see meals without a price',
                      value: _provider.mealPricingEnabled,
                      onChanged: _provider.isSaving
                          ? null
                          : (v) => _provider.toggleMealPricing(
                                organizationId: _orgId,
                                groupId: _provider.selectedGroup!.id,
                                enabled: v,
                              ),
                    ),
                    const SizedBox(height: 12),

                    // ── Opt-out trust model (SRS FR-TRUST-001, Pass 7) ─────
                    _ToggleTile(
                      icon: Icons.how_to_reg_rounded,
                      title: 'Opt-Out Attendance',
                      subtitle: _provider.optOutAttendance
                          ? 'Unmarked members are auto-marked Present at window '
                              'close (they can correct it). Communicate this '
                              'policy to your members.'
                          : 'Opt-in (default): not marking means not counted '
                              'or billed',
                      value: _provider.optOutAttendance,
                      onChanged: _provider.isSaving
                          ? null
                          : (v) => _provider.setAttendanceDefault(
                                organizationId: _orgId,
                                groupId: _provider.selectedGroup!.id,
                                optOut: v,
                              ),
                    ),
                    const SizedBox(height: 12),

                    // ── Hosted guests (Module 22, Pass 9) ──────────────────
                    _ToggleTile(
                      icon: Icons.group_add_rounded,
                      title: 'Hosted Guests (+N)',
                      subtitle: _provider.guestConfig.guestAttendanceEnabled
                          ? 'Members can bring guests — billed to the host. '
                              'Tap "Guest settings" below for caps & pricing.'
                          : 'Members cannot add guests to their meals',
                      value: _provider.guestConfig.guestAttendanceEnabled,
                      onChanged: _provider.isSaving
                          ? null
                          : (v) => _provider.updateGuestConfig(
                                organizationId: _orgId,
                                groupId: _provider.selectedGroup!.id,
                                config: _provider.guestConfig
                                    .copyWith(guestAttendanceEnabled: v),
                              ),
                    ),
                    if (_provider.guestConfig.guestAttendanceEnabled) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _provider.isSaving
                              ? null
                              : _openGuestSettings,
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Guest settings'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),

                    // ── Vacation approval (Pass 11, FR-VACX-001) ───────────
                    _ToggleTile(
                      icon: Icons.beach_access_rounded,
                      title: 'Vacation Needs Approval',
                      subtitle: (_provider.selectedGroup?.mealConfig
                                  .vacationRequiresApproval ??
                              false)
                          ? 'Members submit a dated request you approve — the '
                              'instant self-service toggle is disabled'
                          : 'Members may also use the instant vacation toggle',
                      value: _provider.selectedGroup?.mealConfig
                              .vacationRequiresApproval ??
                          false,
                      onChanged: _provider.isSaving
                          ? null
                          : (v) => _provider.setVacationRequiresApproval(
                                organizationId: _orgId,
                                groupId: _provider.selectedGroup!.id,
                                enabled: v,
                              ),
                    ),
                    const SizedBox(height: 12),

                    // ── Billing cycle (Pass 12, FR-BILLX-020) ──────────────
                    if (_provider.mealPricingEnabled) ...[
                      _BillingCycleTile(
                        day: _provider.selectedGroup?.mealConfig
                            .billingCycleStartDay,
                        saving: _provider.isSaving,
                        onChanged: (d) => _provider.setBillingCycleStartDay(
                          organizationId: _orgId,
                          groupId: _provider.selectedGroup!.id,
                          day: d,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 12),

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
                          // Module 36 (FR-PG-080): per-meal preference builder.
                          onPreferences: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PreferenceGroupsScreen(meal: meal),
                            ),
                          ),
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
                pricingEnabled: _provider.mealPricingEnabled,
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
                    price: data.price,
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
                pricingEnabled: _provider.mealPricingEnabled,
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
                    // null = leave the existing photo untouched (an unchanged
                    // network/migrated photo); empty list = photo removed (clear
                    // server-side); non-empty = replace.
                    imageBytes: data.imageUntouched ? null : data.imageBytes,
                    price: data.price,
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

// ── Billing cycle start day (Pass 12, FR-BILLX-020) ──────────────────────────

class _BillingCycleTile extends StatelessWidget {
  const _BillingCycleTile({
    required this.day,
    required this.saving,
    required this.onChanged,
  });

  final int? day;
  final bool saving;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effective = day ?? 1;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? AppColors.borderDark : AppColors.border)
              .withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded,
              color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Billing Cycle Start Day',
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  effective <= 1
                      ? 'Calendar month (1st → month end)'
                      : 'Runs the $effective${_ord(effective)} → ${effective - 1}${_ord(effective - 1)} of the next month',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          DropdownButton<int>(
            value: effective.clamp(1, 28),
            underline: const SizedBox.shrink(),
            items: [
              for (var d = 1; d <= 28; d++)
                DropdownMenuItem(
                  value: d,
                  child: Text(d == 1 ? '1st (month)' : '$d${_ord(d)}'),
                ),
            ],
            onChanged: saving
                ? null
                : (v) {
                    if (v != null && v != effective) onChanged(v);
                  },
          ),
        ],
      ),
    );
  }

  static String _ord(int d) {
    if (d >= 11 && d <= 13) return 'th';
    return switch (d % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Colour-tinted icon pill that brightens when the toggle is ON.
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: value ? 0.14 : 0.07),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 19,
              color: value ? AppColors.primary : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
    required this.onPreferences,
  });

  final MealModel meal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  /// Module 36 (FR-PG-080): opens the preference-group builder for this meal.
  final VoidCallback onPreferences;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = MealModel.iconBgColor(meal.order);
    final fg = MealModel.iconFgColor(meal.order);

    return Opacity(
      // Dim a disabled meal so its On/Off state reads at a glance.
      opacity: meal.isActive ? 1.0 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon — per-meal colour for a premium, scannable list.
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(meal.icon, size: 20, color: fg),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Each fact is its own chip so nothing merges/overflows (the
                  // ₹ price used to crowd the time + item count); Wrap makes it
                  // responsive on narrow screens.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _MetaChip(
                        icon: Icons.schedule_rounded,
                        label: TimeFormat.window12(
                          meal.attendanceWindow.openTime,
                          meal.attendanceWindow.closeTime,
                        ),
                        isDark: isDark,
                      ),
                      if (meal.menuItems.isNotEmpty)
                        _MetaChip(
                          icon: Icons.restaurant_menu_rounded,
                          label: '${meal.menuItems.length} items',
                          isDark: isDark,
                        ),
                      if (meal.price != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '₹${meal.price}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
                value: _MealAction.preferences,
                child: Text('Preference Groups'),
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
                case _MealAction.preferences:
                  onPreferences();
                case _MealAction.delete:
                  onDelete();
              }
            },
          ),
        ],
      ),
      ),
    );
  }
}

/// Premium metadata pill for the meal tile (icon + short label). Keeps each
/// fact visually separate so the time / item-count / ₹ price never merge.
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final c = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isDark ? AppColors.surfaceVariantDark : AppColors.surfaceVariant)
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: c),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: c,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum _MealAction { toggle, edit, preferences, delete }

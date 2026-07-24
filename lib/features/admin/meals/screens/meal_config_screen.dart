import 'package:flutter/material.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_meal_management/app/router/route_names.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
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
import 'package:smart_meal_management/shared/widgets/app_skeleton.dart';

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
          // Live-Test-8 ISSUE-003: the planner is a MEAL surface — when the
          // meal system is OFF it must disappear for admins exactly as the
          // menu tabs do for members (state is preserved server-side and the
          // button returns the moment meals are re-enabled).
          if (_provider.selectedGroup != null && _provider.mealsEnabled)
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
      // SRS Module 03 MODE-003: Attendance-Only groups manage their Master
      // Attendance Template here — the FAB adds a window instead of a meal.
      floatingActionButton: _provider.selectedGroup != null
          ? FloatingActionButton.extended(
              onPressed: () => _provider.mealsEnabled
                  ? _showAddMealSheet(context)
                  : _showWindowSheet(),
              icon: const Icon(Icons.add_rounded),
              label:
                  Text(_provider.mealsEnabled ? 'Add Meal' : 'Add Window'),
            )
          : null,
      body: _provider.isLoading
          ? const AppListSkeleton(rows: 4, rowHeight: 104, headerHeight: 48)
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
                  const AppSheetSkeleton(rows: 3, rowHeight: 104, padding: EdgeInsets.symmetric(vertical: 24)),
                ] else ...[
                  // ── Master meal toggle ───────────────────────────────────
                  // Wording: one-line explainer so a new admin knows what the
                  // Master Meal Template is before meeting the toggles.
                  const AppSectionTitle(
                    title: 'Meal System',
                    subtitle:
                        'Define this group\'s meals once here — the weekly '
                        'planner, daily plans and member menus all build from '
                        'this master list',
                  ),
                  const SizedBox(height: 12),
                  _ToggleTile(
                    icon: Icons.restaurant_rounded,
                    title: 'Meals Enabled',
                    subtitle: _provider.mealsEnabled
                        ? 'Members can view menus and mark meal attendance'
                        : 'Attendance-only mode — meal UI hidden from members',
                    value: _provider.mealsEnabled,
                    onChanged: (v) => _provider.toggleMealSystem(
                              organizationId: _orgId,
                              groupId:
                                  _provider.selectedGroup!.id,
                              enabled: v,
                            ),
                  ),
                  const SizedBox(height: 12),

                  if (_provider.mealsEnabled) ...[
                    // ── Preferences toggle ─────────────────────────────────
                    // SRS Module 03 ATT-007: mutually exclusive with
                    // Auto-Present — greyed (only while OFF, so a legacy
                    // both-ON group can still switch it off) with an info
                    // subtitle instead of failing after the tap.
                    _ToggleTile(
                      icon: Icons.tune_rounded,
                      title: 'Meal Preferences',
                      subtitle: (!_provider.preferencesEnabled &&
                              _provider.optOutAttendance)
                          ? 'Unavailable while Auto-Present is ON — automatic '
                              'attendance can\'t pick preferences for members. '
                              'Turn off Auto-Present first.'
                          : _provider.preferencesEnabled
                              ? 'Members tag Veg/Chicken/Fish etc. before attendance'
                              : 'No preference selection — just mark present/absent',
                      value: _provider.preferencesEnabled,
                      onChanged: ((!_provider.preferencesEnabled &&
                                  _provider.optOutAttendance))
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
                      onChanged: (v) => _provider.toggleMealPricing(
                                organizationId: _orgId,
                                groupId: _provider.selectedGroup!.id,
                                enabled: v,
                              ),
                    ),
                    const SizedBox(height: 12),

                    // ── Billing policy (SRS Module 03 Q17/Q22 + Live-Test-11
                    // ISSUE-017): TWO independent date-forward toggles. Each
                    // affects meals from the next mark/window-close onwards,
                    // never past bills (the server snapshots the policy onto
                    // each record at write time).
                    if (_provider.mealPricingEnabled) ...[
                      _ToggleTile(
                        icon: Icons.rule_folder_rounded,
                        title: 'Bill Skipped Meals',
                        subtitle: (_provider.selectedGroup?.mealConfig
                                    .billSkippedMeals ??
                                false)
                            ? 'Unmarked (no-response) meals are billed at the '
                                'scheduled price from the next meal onwards.'
                            : 'Unmarked (no-response) meals are free.',
                        value: _provider.selectedGroup?.mealConfig
                                .billSkippedMeals ??
                            false,
                        onChanged: (v) => _provider.toggleBillSkippedMeals(
                                  organizationId: _orgId,
                                  groupId: _provider.selectedGroup!.id,
                                  enabled: v,
                                ),
                      ),
                      const SizedBox(height: 12),
                      // Live-Test-11 ISSUE-017 (survey-locked): independent
                      // Bill-Absent policy — snapshotted per record at mark
                      // time, so only FUTURE absents are affected by a flip.
                      _ToggleTile(
                        icon: Icons.event_busy_rounded,
                        title: 'Bill Absent Meals',
                        subtitle: (_provider.selectedGroup?.mealConfig
                                    .billAbsentMeals ??
                                false)
                            ? 'Meals marked Absent are billed at the scheduled '
                                'price from the next meal onwards. Past bills '
                                'never change.'
                            : 'Meals marked Absent are free.',
                        value: _provider.selectedGroup?.mealConfig
                                .billAbsentMeals ??
                            false,
                        onChanged: (v) => _provider.toggleBillAbsentMeals(
                                  organizationId: _orgId,
                                  groupId: _provider.selectedGroup!.id,
                                  enabled: v,
                                ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Opt-out trust model (SRS FR-TRUST-001, Pass 7) ─────
                    // SRS Module 03 ATT-007: mutually exclusive with Meal
                    // Preferences (see the Preferences tile above). Renamed
                    // from "Opt-Out Attendance" — "Auto-Present" says what it
                    // actually does; new admins don't know opt-out jargon.
                    _ToggleTile(
                      icon: Icons.how_to_reg_rounded,
                      title: 'Auto-Present Attendance',
                      subtitle: (!_provider.optOutAttendance &&
                              _provider.preferencesEnabled)
                          ? 'Unavailable while Meal Preferences is ON — the '
                              'system can\'t pick preferences for members. '
                              'Turn off Meal Preferences first.'
                          : _provider.optOutAttendance
                              ? 'Members who don\'t mark anything are automatically '
                                  'marked Present when the window closes (they can '
                                  'correct it). Tell your members about this policy.'
                              : 'OFF (default): members mark themselves — no mark '
                                  'means not counted and not billed',
                      value: _provider.optOutAttendance,
                      onChanged: ((!_provider.optOutAttendance &&
                                  _provider.preferencesEnabled))
                          ? null
                          : (v) => _provider.setAttendanceDefault(
                                organizationId: _orgId,
                                groupId: _provider.selectedGroup!.id,
                                optOut: v,
                              ),
                    ),
                    const SizedBox(height: 12),

                    // ── Hosted guests (Module 22, Pass 9) ──────────────────
                    // Wording: "Hosted Guests (+N)" read as jargon to new
                    // admins — "Guest Meals" says what it is.
                    _ToggleTile(
                      icon: Icons.group_add_rounded,
                      title: 'Guest Meals',
                      subtitle: _provider.guestConfig.guestAttendanceEnabled
                          ? 'Members can bring guests to a meal — the extra plates '
                              'are billed to the member who booked them. Tap '
                              '"Guest settings" below for limits & pricing.'
                          : 'Members cannot add guests to their meals',
                      value: _provider.guestConfig.guestAttendanceEnabled,
                      onChanged: (v) => _provider.updateGuestConfig(
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
                          onPressed: _openGuestSettings,
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
                      onChanged: (v) => _provider.setVacationRequiresApproval(
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
                        // ISSUE-004: patches are queued + optimistic — the
                        // picker stays interactive during a save.
                        saving: false,
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
                            'Meal menus and timelines are hidden. Members mark attendance in the windows below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── SRS Module 03 MODE-003: Master Attendance Template ──
                    const SizedBox(height: 20),
                    AppSectionTitle(
                      title: 'Attendance Windows',
                      subtitle:
                          '${_windowMeals.length} of 5 — applied automatically every day',
                    ),
                    const SizedBox(height: 12),
                    if (_windowMeals.isEmpty)
                      const AppEmptyState(
                        icon: Icons.schedule_rounded,
                        title: 'No attendance windows yet',
                        subtitle:
                            'Tap + Add Window to create one (e.g. "Morning Attendance", 7:00–8:00 AM).',
                      )
                    else
                      ..._windowMeals.map(
                        (w) => Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const Icon(Icons.schedule_rounded,
                                color: AppColors.primary),
                            title: Text(w.name,
                                style: AppTypography.bodyMedium
                                    .copyWith(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${TimeFormat.hm12(w.attendanceWindow.openTime)} – ${TimeFormat.hm12(w.attendanceWindow.closeTime)}'
                              '${w.isActive ? '' : '  ·  Disabled'}',
                              style: AppTypography.labelSmall
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            onTap: () => _showWindowSheet(window: w),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: w.isActive,
                                  onChanged: (v) => _provider.updateMeal(
                                            organizationId: _orgId,
                                            groupId: w.groupId,
                                            mealId: w.id,
                                            isActive: v,
                                          ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded,
                                      size: 20, color: AppColors.error),
                                  onPressed: () => _confirmDelete(context, w),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ],
            ),
    );
  }

  /// MODE-003: the group's attendance windows (window-only meal rows). The
  /// implicit general-attendance slot never appears in the template.
  List<MealModel> get _windowMeals =>
      _provider.meals.where((m) => !m.isGeneralAttendance).toList();

  /// MODE-003: create/edit one Master Attendance Template window —
  /// name + open/close times only (no menus, pricing or preferences).
  Future<void> _showWindowSheet({MealModel? window}) async {
    final nameCtrl = TextEditingController(text: window?.name ?? '');
    TimeOfDay open = _parseHHmm(window?.attendanceWindow.openTime) ??
        const TimeOfDay(hour: 7, minute: 0);
    TimeOfDay close = _parseHHmm(window?.attendanceWindow.closeTime) ??
        const TimeOfDay(hour: 8, minute: 0);
    String? sheetError;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                window == null ? 'Add Attendance Window' : 'Edit Window',
                style: AppTypography.titleMedium
                    .copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: 'Window name',
                  hintText: 'e.g. Morning Attendance',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: Text('Opens ${open.format(ctx)}'),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: open);
                        if (t != null) setSheet(() => open = t);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.logout_rounded, size: 16),
                      label: Text('Closes ${close.format(ctx)}'),
                      onPressed: () async {
                        final t = await showTimePicker(
                            context: ctx, initialTime: close);
                        if (t != null) setSheet(() => close = t);
                      },
                    ),
                  ),
                ],
              ),
              if (sheetError != null) ...[
                const SizedBox(height: 8),
                Text(sheetError!,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty) {
                      setSheet(() => sheetError = 'Window name is required.');
                      return;
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  child: Text(window == null ? 'Add window' : 'Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;
    String hhmm(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final win = MealAttendanceWindow(
        openTime: hhmm(open), closeTime: hhmm(close));
    final name = nameCtrl.text.trim();
    if (window == null) {
      await _provider.createMeal(
        organizationId: _orgId,
        groupId: _provider.selectedGroup!.id,
        name: name,
        slotKey: 'window-${DateTime.now().millisecondsSinceEpoch}',
        order: _windowMeals.length,
        attendanceWindow: win,
      );
    } else {
      await _provider.updateMeal(
        organizationId: _orgId,
        groupId: window.groupId,
        mealId: window.id,
        name: name,
        attendanceWindow: win,
      );
    }
    if (mounted && _provider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_provider.error!)),
      );
    }
  }

  static TimeOfDay? _parseHHmm(String? s) {
    if (s == null || s.length < 4) return null;
    final parts = s.split(':');
    final h = int.tryParse(parts[0]);
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  void _showAddMealSheet(BuildContext context) {
    // Live-Test-9 ISSUE-001 (MMT-001): friendly pre-save gate on the 10-meal
    // Master Meal Template cap — the server enforces the same limit (422),
    // which the form now also shows inline, but blocking here saves the admin
    // from filling a whole form first. Archived meals don't count.
    final activeCount = _provider.meals.where((m) => m.isActive).length;
    if (activeCount >= AppConstants.maxMasterMealsPerGroup) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Meal limit reached'),
          content: const Text(
            'Maximum ${AppConstants.maxMasterMealsPerGroup} Master Meals are '
            'allowed. Please delete an existing meal before creating a new one.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
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
                isSaving: false, // the form owns its own submit lifecycle
                // Inherit global preference state — new meals default ON
                // when the group's preference toggle is already enabled.
                initialPreferencesEnabled: _provider.preferencesEnabled,
                // ISSUE-011: Global OFF locks the per-meal toggle (read-only).
                globalPreferencesEnabled: _provider.preferencesEnabled,
                pricingEnabled: _provider.mealPricingEnabled,
                // Live-Test-9 ISSUE-001: pop the SHEET'S OWN route, ONLY on
                // success. The old handler captured the SCREEN's navigator and
                // popped unconditionally after the await — a failed save
                // closed the sheet (entered data lost, error invisible), and
                // rapid taps stacked multiple pops that emptied the navigator
                // into a black screen requiring a cold restart.
                onSave: (data) async {
                  final group = _provider.selectedGroup;
                  if (group == null) return 'No group selected.';
                  final created = await _provider.createMeal(
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
                  if (created == null) {
                    return _provider.error ??
                        'Could not save the meal. Please try again.';
                  }
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  return null;
                },
                // Live-Test-9 ISSUE-5.2: Preference Groups on a NEW meal —
                // save it (groups need a meal id), close the sheet and open
                // the Groups builder for the freshly created meal in one
                // seamless step. Flat tags stay empty: Groups mode governs.
                onSaveForGroups: (data) async {
                  final group = _provider.selectedGroup;
                  if (group == null) return 'No group selected.';
                  final created = await _provider.createMeal(
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
                    availablePreferences: const [],
                    imageBytes: data.imageBytes,
                    price: data.price,
                  );
                  if (created == null) {
                    return _provider.error ??
                        'Could not save the meal. Please try again.';
                  }
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  if (mounted) {
                    await Navigator.of(this.context).push(MaterialPageRoute(
                      builder: (_) => PreferenceGroupsScreen(meal: created),
                    ));
                  }
                  return null;
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
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
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
                isSaving: false, // the form owns its own submit lifecycle
                // ISSUE-011: Global OFF locks the per-meal toggle (read-only).
                globalPreferencesEnabled: _provider.preferencesEnabled,
                pricingEnabled: _provider.mealPricingEnabled,
                // Live-Test-9 ISSUE-001: pop the SHEET'S OWN route, ONLY on
                // success — see _showAddMealSheet for the failure analysis.
                onSave: (data) async {
                  final ok = await _provider.updateMeal(
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
                  if (!ok) {
                    return _provider.error ??
                        'Could not save the changes. Please try again.';
                  }
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  return null;
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
        // MMT-011/012 wording: say exactly what happens instead of a vague
        // "cannot be undone" — the meal leaves future plans, members keep the
        // currently published menu until re-publish, history stays intact.
        content: const Text(
          'This meal is removed from upcoming plans and menus. Members keep '
          'seeing the currently published menu until you publish again. Past '
          'attendance and billing records are kept.',
        ),
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
          // SRS Module 03 BILL-012 (survey Q20): anchor days 1–31 all valid —
          // a day missing from a short month clamps to its last calendar day
          // server-side (the configured value never changes).
          DropdownButton<int>(
            value: effective.clamp(1, 31),
            underline: const SizedBox.shrink(),
            items: [
              for (var d = 1; d <= 31; d++)
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
                      // ISSUE-007A: the meal's preference configuration is
                      // VISIBLE on the card — groups mode shows the group
                      // count/label, standalone mode the tag count. Violet
                      // accent tint reads clearly in light AND dark theme.
                      if (meal.preferenceGroups.isNotEmpty)
                        _PrefChip(
                          icon: Icons.account_tree_rounded,
                          label: meal.preferenceGroups.length == 1
                              ? meal.preferenceGroups.first.label
                              : '${meal.preferenceGroups.length} pref groups',
                        )
                      else if (meal.hasPreferences &&
                          meal.enabledPreferences.isNotEmpty)
                        _PrefChip(
                          icon: Icons.local_offer_rounded,
                          label:
                              '${meal.enabledPreferences.length} pref tags',
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

/// ISSUE-007A: violet preference pill for the meal tile — high-contrast in
/// BOTH themes so the configured preference groups/tags are always visible.
class _PrefChip extends StatelessWidget {
  const _PrefChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.violet.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.violet.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.violet),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.violet,
              ),
            ),
          ),
        ],
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

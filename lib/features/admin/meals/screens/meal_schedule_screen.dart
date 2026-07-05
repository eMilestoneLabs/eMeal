import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:smart_meal_management/features/admin/meals/providers/meal_config_provider.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/preference_group_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/widgets/app_empty_state.dart';
import 'package:smart_meal_management/shared/widgets/app_loading_indicator.dart';
import 'package:smart_meal_management/features/auth/providers/auth_provider.dart';

/// Admin Weekly Meal Planner.
///
/// Architecture guarantee: each weekday maintains COMPLETELY independent meal
/// data.  Editing Monday's Breakfast items does not affect any other day.
/// This is achieved by surfacing [DayMealEntry] objects (per-day copies) in
/// the UI rather than shared [MealModel] templates.
///
/// Tabs: Mon–Sun, today highlighted, responsive layout via TabAlignment.fill.
/// Publish FAB: visible when schedule is in Draft state.
/// Preview mode: read-only student-facing view of the same data.
class MealScheduleScreen extends StatefulWidget {
  const MealScheduleScreen({
    super.key,
    this.initialGroupId,
    this.dayWiseMode = false,
  });

  /// Group whose weekly schedule to open — carried from Meal Config so the
  /// planner edits the SAME group the admin selected. Null -> first group.
  final String? initialGroupId;

  /// When true, the planner runs in DAY-WISE mode: it shows ONLY Today and
  /// Tomorrow (no weekly tabs, no recurring/copy-week actions). When false the
  /// planner behaves exactly as the existing Weekly Planner (unchanged).
  final bool dayWiseMode;

  @override
  State<MealScheduleScreen> createState() => _MealScheduleScreenState();
}

class _MealScheduleScreenState extends State<MealScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final MealConfigProvider _provider;
  late final TabController _tabController;
  bool _initialized = false;
  bool _previewMode = false;
  // True from the first frame until the initial loadGroups->loadSchedule chain
  // completes, so the planner shows a loader (never the "No schedule yet" empty
  // state) during the gap between those two sequential fetches.
  bool _bootstrapping = true;

  /// Days shown in the planner. Weekly mode = all 7 weekdays (unchanged).
  /// Day-Wise mode = only [Today, Tomorrow] — strictly a two-day window.
  List<DayOfWeek> get _days => widget.dayWiseMode
      ? <DayOfWeek>[
          DayOfWeek.fromWeekday(DateTime.now().weekday),
          DayOfWeek.fromWeekday(
              DateTime.now().add(const Duration(days: 1)).weekday),
        ]
      : DayOfWeek.values;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _days.length, vsync: this);
    // Day-Wise opens on Today (index 0). Weekly opens on the current weekday.
    _tabController.index = widget.dayWiseMode
        ? 0
        : DayOfWeek.fromWeekday(DateTime.now().weekday).index;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _provider = MealConfigProvider();
      _provider.addListener(_rebuild);
      final auth = AuthProviderScope.of(context);
      final user = auth.currentUser;
      if (user == null) {
        _bootstrapping = false;
        return;
      }
      final orgId = user.organizationId;
      _provider.loadGroups(organizationId: orgId).then((_) async {
        // Issue 1: edit the SAME group selected in Meal Config (carried as
        // ?groupId=). Fall back to the auto-selected first group otherwise.
        final wanted = widget.initialGroupId;
        if (wanted != null &&
            wanted.isNotEmpty &&
            _provider.selectedGroup?.id != wanted) {
          GroupModel? target;
          for (final g in _provider.groups) {
            if (g.id == wanted) {
              target = g;
              break;
            }
          }
          if (target != null) {
            await _provider.selectGroup(target, organizationId: orgId);
          }
        }
        final sel = _provider.selectedGroup;
        if (sel != null) {
          await _provider.loadSchedule(organizationId: orgId, groupId: sel.id);
        }
      }).whenComplete(() {
        // Initial load chain finished (or failed) — drop the bootstrap loader.
        if (mounted) setState(() => _bootstrapping = false);
      });
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabController.dispose();
    _provider.removeListener(_rebuild);
    _provider.dispose();
    super.dispose();
  }

  void _togglePreview() => setState(() => _previewMode = !_previewMode);

  /// Switch the planner to another group (group selector). Loads that group's
  /// meals + weekly schedule. Additive (Issue 1) — lets the admin pick which
  /// group's schedule to edit without leaving the planner.
  Future<void> _selectPlannerGroup(GroupModel group) async {
    if (_provider.selectedGroup?.id == group.id) return;
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    final orgId = user.organizationId;
    await _provider.selectGroup(group, organizationId: orgId);
    await _provider.loadSchedule(organizationId: orgId, groupId: group.id);
  }

  Future<void> _copyFromPreviousWeek() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy from previous week?'),
        content: const Text(
          'All active meals will be enabled on every day, each with its '
          'template menu items.  You can then edit each day independently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _provider.copyFromPreviousWeek();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Schedule copied — edit each day independently'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Enhancement 3: toggle 'Continue Recurring Weekly Menu' for the selected
  /// group. When ON, an empty week auto-fills from the last published week.
  Future<void> _toggleRecurring() async {
    final g = _provider.selectedGroup;
    if (g == null) return;
    final next = !_provider.autoContinueLastWeek;
    await _provider.setAutoContinueLastWeek(next, groupId: g.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Recurring weekly menu ON — an empty week auto-fills from the last published week'
                : 'Recurring weekly menu OFF',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: next ? AppColors.present : null,
        ),
      );
    }
  }

  Future<void> _publishSchedule() async {
    if (_provider.selectedGroup == null) return;
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    final orgId = user.organizationId;
    final ok = await _provider.publishSchedule(
      organizationId: orgId,
      groupId: _provider.selectedGroup!.id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Schedule published — members can see it now'
                : _provider.error ?? 'Failed to publish',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ok ? AppColors.present : AppColors.error,
        ),
      );
    }
  }

  /// Issue 2: revert a published schedule back to draft so it can be edited and
  /// re-published. After success the schedule is unpublished and the Publish
  /// FAB reappears.
  Future<void> _revertSchedule() async {
    if (_provider.selectedGroup == null) return;
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;
    final orgId = user.organizationId;
    final ok = await _provider.revertToDraft(
      organizationId: orgId,
      groupId: _provider.selectedGroup!.id,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Reverted to draft — edit each day, then publish again'
                : _provider.error ?? 'Failed to revert',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ok ? AppColors.warning : AppColors.error,
        ),
      );
    }
  }

  /// Pass 15 (FR-SCHX-003): full UNPUBLISH — hide the week from students
  /// entirely. Distinct from Revert to Draft (which keeps the last published
  /// week visible while editing); the draft + last snapshot stay recoverable
  /// on the server, so re-publishing restores it. Confirmed first because it
  /// removes what members currently see.
  Future<void> _unpublishHide() async {
    if (_provider.selectedGroup == null) return;
    final auth = AuthProviderScope.of(context);
    final user = auth.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Unpublish this week?'),
        content: const Text(
          'Students will no longer see this week\'s menu. Your draft is kept '
          'and you can publish again anytime to restore it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Unpublish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final orgId = user.organizationId;
    final ok = await _provider.revertToDraft(
      organizationId: orgId,
      groupId: _provider.selectedGroup!.id,
      hide: true,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Unpublished — hidden from students. Publish again to restore.'
                : _provider.error ?? 'Failed to unpublish',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: ok ? AppColors.warning : AppColors.error,
        ),
      );
    }
  }

  /// Opens the per-day meal editor for [day] + [mealId].
  /// Changes made in the sheet call [MealConfigProvider.updateDayMealEntry]
  /// which updates ONLY that day's entry — all other days are untouched.
  void _openDayMealEditor(DayOfWeek day, String mealId) {
    final daySchedule = _provider.weekSchedule?.forDay(day);
    DayMealEntry? entry;
    for (final e in (daySchedule?.meals ?? <DayMealEntry>[])) {
      if (e.mealId == mealId) {
        entry = e;
        break;
      }
    }
    MealModel? template;
    for (final m in _provider.meals) {
      if (m.id == mealId) {
        template = m;
        break;
      }
    }
    if (entry == null || template == null) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DayMealEditSheet(
        day: day,
        entry: entry!,
        templateName: template!.name,
        templateMenuItems: template.menuItems,
        templateDescription: template.description,
        templateOpenTime: template.attendanceWindow.openTime,
        templateCloseTime: template.attendanceWindow.closeTime,
        templatePreferenceOptions: template.enabledPreferences.isNotEmpty
            ? template.enabledPreferences
            : const ['veg', 'chicken', 'fish', 'mutton', 'egg', 'jain'],
        templatePreferenceGroups: template.preferenceGroups,
        pricingEnabled: _provider.mealPricingEnabled,
        templatePrice: template.price,
        onSave: ({
          required String name,
          required List<String> menuItems,
          String? description,
          List<Uint8List>? imageBytes,
          String? openTime,
          String? closeTime,
          required bool preferencesEnabled,
          required List<String> enabledPreferences,
          required List<String> enabledPreferenceGroupIds,
          int? price,
        }) {
          _provider.updateDayMealEntry(
            day,
            mealId,
            name: name,
            menuItems: menuItems,
            description: description,
            clearDescription: description == null,
            imageBytes: imageBytes,
            openTime: openTime,
            closeTime: closeTime,
            preferencesEnabled: preferencesEnabled,
            enabledPreferences: enabledPreferences,
            enabledPreferenceGroupIds: enabledPreferenceGroupIds,
            price: price,
            clearPrice: price == null,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPublished = _provider.weekSchedule?.isPublished == true;
    final today = DayOfWeek.fromWeekday(DateTime.now().weekday);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      floatingActionButton: (!_previewMode &&
              !isPublished &&
              _provider.weekSchedule != null &&
              !_provider.isLoading)
          ? FloatingActionButton.extended(
              onPressed: _provider.isSaving ? null : _publishSchedule,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: _provider.isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.publish_rounded, size: 20),
              label: Text(
                _provider.isSaving
                    ? 'Publishing…'
                    : (widget.dayWiseMode
                        ? 'Publish Day Plan'
                        : 'Publish Schedule'),
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.dayWiseMode ? 'Daily Meal Plan' : 'Weekly Planner',
                style: AppTypography.titleLarge),
            if (_previewMode)
              Text(
                'Preview · student view',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.info,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _togglePreview,
            tooltip: _previewMode ? 'Exit preview' : 'Preview student view',
            icon: Icon(
              _previewMode ? Icons.edit_rounded : Icons.visibility_rounded,
              color: _previewMode ? AppColors.info : null,
            ),
          ),
          // Weekly-only actions (copy previous week / recurring) are hidden in
          // Day-Wise mode — those are weekly scheduling concepts. Revert-to-draft
          // applies to both since publishing is shared.
          if (!widget.dayWiseMode || isPublished)
            PopupMenuButton<_ScheduleAction>(
              icon: const Icon(Icons.more_vert_rounded),
              itemBuilder: (_) => [
                if (!widget.dayWiseMode)
                  const PopupMenuItem(
                    value: _ScheduleAction.copyPrevious,
                    child: Row(
                      children: [
                        Icon(Icons.copy_all_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Copy from previous week'),
                      ],
                    ),
                  ),
                if (!widget.dayWiseMode)
                  PopupMenuItem(
                    value: _ScheduleAction.toggleRecurring,
                    child: Row(
                      children: [
                        Icon(
                          _provider.autoContinueLastWeek
                              ? Icons.event_repeat_rounded
                              : Icons.event_repeat_outlined,
                          size: 18,
                          color: _provider.autoContinueLastWeek
                              ? AppColors.present
                              : null,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Continue Recurring Weekly Menu'),
                        ),
                        if (_provider.autoContinueLastWeek)
                          const Icon(Icons.check_rounded,
                              size: 16, color: AppColors.present),
                      ],
                    ),
                  ),
                if (isPublished)
                  const PopupMenuItem(
                    value: _ScheduleAction.revertToDraft,
                    child: Row(
                      children: [
                        Icon(Icons.undo_rounded,
                            size: 18, color: AppColors.warning),
                        SizedBox(width: 10),
                        Text('Revert to Draft'),
                      ],
                    ),
                  ),
                // Pass 15 (FR-SCHX-003): full unpublish — hide the week from
                // students entirely (distinct from Revert to Draft, which
                // keeps the last published week visible while editing).
                if (isPublished)
                  const PopupMenuItem(
                    value: _ScheduleAction.unpublishHide,
                    child: Row(
                      children: [
                        Icon(Icons.visibility_off_rounded,
                            size: 18, color: AppColors.error),
                        SizedBox(width: 10),
                        Expanded(child: Text('Unpublish (hide from students)')),
                      ],
                    ),
                  ),
              ],
              onSelected: (action) {
                switch (action) {
                  case _ScheduleAction.copyPrevious:
                    _copyFromPreviousWeek();
                  case _ScheduleAction.revertToDraft:
                    _revertSchedule();
                  case _ScheduleAction.unpublishHide:
                    _unpublishHide();
                  case _ScheduleAction.toggleRecurring:
                    _toggleRecurring();
                }
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          // isScrollable: false + TabAlignment.fill = equal-width responsive
          // tabs distributed across the full bar width.  Never wraps labels,
          // never triggers the "fill is only valid for non-scrollable" assertion.
          isScrollable: false,
          tabAlignment: TabAlignment.fill,
          labelStyle:
              AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700),
          unselectedLabelStyle: AppTypography.labelMedium,
          labelColor: AppColors.primary,
          unselectedLabelColor: isDark
              ? AppColors.textSecondaryDark
              : AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          dividerColor: isDark ? AppColors.borderDark : AppColors.border,
          tabs: _days.asMap().entries.map((e) {
            final i = e.key;
            final d = e.value;
            final isToday = d == today;
            // Day-Wise: label tabs "Today"/"Tomorrow" + the weekday name.
            final label = widget.dayWiseMode
                ? '${i == 0 ? 'Today' : 'Tomorrow'} · ${d.label}'
                : d.label;
            return Tab(
              height: 40,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontWeight:
                      isToday ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ),
      body: (_provider.isLoading || _bootstrapping)
          ? const AppLoadingIndicator()
          : _provider.weekSchedule == null
              ? AppEmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'No schedule yet',
                  subtitle: widget.dayWiseMode
                      ? 'Add meals in Master Meal Template first — they become the daily template for Today and Tomorrow.'
                      : 'Configure meals first, then build your weekly schedule here.',
                )
              : Column(
                  children: [
                    if (_provider.groups.length > 1 && !_previewMode)
                      _PlannerGroupSelector(
                        groups: _provider.groups,
                        selectedId: _provider.selectedGroup?.id,
                        onSelect: _selectPlannerGroup,
                      ),
                    _StatusBanner(
                      isPublished: isPublished,
                      isPreview: _previewMode,
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: _days.map((day) {
                          return _DayPlanView(
                            key: ValueKey(day),
                            day: day,
                            allMeals: _provider.meals,
                            schedule: _provider.weekSchedule,
                            readOnly: _previewMode,
                            onToggle: _previewMode
                                ? null
                                : (mealId, enabled) =>
                                    _provider.toggleMealDay(
                                      mealId,
                                      day.index,
                                      enabled,
                                    ),
                            onEdit: _previewMode
                                ? null
                                : (mealId) =>
                                    _openDayMealEditor(day, mealId),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
    );
  }
}

// ── Status banner ──────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.isPublished, required this.isPreview});
  final bool isPublished;
  final bool isPreview;

  @override
  Widget build(BuildContext context) {
    if (isPreview) {
      return const _BannerStrip(
        color: AppColors.info,
        icon: Icons.visibility_rounded,
        message: 'Student view — tap ✏️ to return to edit mode.',
      );
    }
    if (isPublished) {
      return const _BannerStrip(
        color: AppColors.present,
        icon: Icons.check_circle_rounded,
        message: 'Published — students can see this schedule.',
      );
    }
    return const _BannerStrip(
      color: AppColors.warning,
      icon: Icons.edit_note_rounded,
      message: 'Draft — edit each day independently, then publish.',
    );
  }
}

class _BannerStrip extends StatelessWidget {
  const _BannerStrip({
    required this.color,
    required this.icon,
    required this.message,
  });
  final Color color;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.10),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Day plan view ──────────────────────────────────────────────────────────────

/// Shows all configurable meal slots for one day.
///
/// For **enabled** meals, the card displays the [DayMealEntry] data (the
/// day-specific independent copy).  For **disabled** meals the card shows
/// the [MealModel] template data in a greyed-out state.
///
/// This separation is what guarantees that editing Monday's items cannot
/// propagate to Saturday — each tab operates on its own [DaySchedule].
class _DayPlanView extends StatelessWidget {
  const _DayPlanView({
    super.key,
    required this.day,
    required this.allMeals,
    required this.schedule,
    required this.readOnly,
    this.onToggle,
    this.onEdit,
  });

  final DayOfWeek day;
  final List<MealModel> allMeals;
  final MealScheduleModel? schedule;
  final bool readOnly;
  final void Function(String mealId, bool enabled)? onToggle;

  /// Called with [mealId] when the edit (pencil) button is tapped.
  final void Function(String mealId)? onEdit;

  @override
  Widget build(BuildContext context) {
    if (allMeals.isEmpty) {
      return const AppEmptyState(
        icon: Icons.restaurant_menu_outlined,
        title: 'No meals configured',
        subtitle: 'Add meals in the Meals tab first.',
      );
    }

    final daySchedule = schedule?.forDay(day);

    // Build a lookup: mealId → DayMealEntry for this specific day.
    final Map<String, DayMealEntry> enabledEntries = {};
    for (final e in (daySchedule?.meals ?? <DayMealEntry>[])) {
      enabledEntries[e.mealId] = e;
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pagePaddingH,
        AppConstants.pagePaddingV,
        AppConstants.pagePaddingH,
        88, // FAB clearance
      ),
      itemCount: allMeals.length,
      separatorBuilder: (_, i) =>
          const SizedBox(height: AppConstants.space12),
      itemBuilder: (context, i) {
        final meal = allMeals[i];
        final dayEntry = enabledEntries[meal.id]; // null = disabled this day
        final isEnabled = dayEntry != null;

        return _MealSlotCard(
          meal: meal,
          dayEntry: dayEntry,
          isEnabled: isEnabled,
          readOnly: readOnly,
          day: day,
          isPublished: schedule?.isPublished == true,
          onToggle: onToggle != null
              ? (v) => onToggle!(meal.id, v)
              : null,
          onEdit: (!readOnly && isEnabled && onEdit != null)
              ? () => onEdit!(meal.id)
              : null,
        );
      },
    );
  }
}

// ── Meal slot card ─────────────────────────────────────────────────────────────

/// Premium operational card for a single meal slot.
///
/// When the meal is enabled ([dayEntry] != null), displays the day-specific
/// [DayMealEntry] data.  When disabled, shows [MealModel] template data.
///
/// The edit (pencil) button opens a per-day editor that never touches other
/// days' entries.
class _MealSlotCard extends StatelessWidget {
  const _MealSlotCard({
    required this.meal,
    required this.dayEntry,
    required this.isEnabled,
    required this.readOnly,
    required this.day,
    required this.isPublished,
    this.onToggle,
    this.onEdit,
  });

  final MealModel meal;

  /// Day-specific entry.  Non-null when this meal is enabled for the day.
  final DayMealEntry? dayEntry;
  final bool isEnabled;
  final bool readOnly;

  /// The weekday this card represents — used for the price-lock indicator.
  final DayOfWeek day;

  /// Whether the parent schedule is published (prerequisite for a locked price).
  final bool isPublished;

  final ValueChanged<bool>? onToggle;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    // Use the day entry's name/items when enabled; fall back to template.
    final displayName =
        isEnabled ? (dayEntry!.name) : meal.name;
    final displayItems =
        isEnabled ? dayEntry!.menuItems : meal.menuItems;
    final displayOpen = isEnabled && dayEntry!.openTime != null
        ? dayEntry!.openTime!
        : meal.attendanceWindow.openTime;
    final displayClose = isEnabled && dayEntry!.closeTime != null
        ? dayEntry!.closeTime!
        : meal.attendanceWindow.closeTime;
    // Additive: per-day price override falls back to the master meal price.
    final displayPrice =
        isEnabled ? (dayEntry!.price ?? meal.price) : meal.price;

    // Price is locked ONLY for TODAY while its attendance window is currently
    // open (open <= now <= close). Past weekdays, future weekdays, today before
    // open, and today after close all stay editable — those edits apply to the
    // next occurrence and never touch a completed day (historical records keep
    // their snapshot). Backend enforces the same rule; this is the indicator.
    bool computePriceLocked() {
      if (!isPublished || displayPrice == null) return false;
      final todayIndex = DayOfWeek.fromWeekday(DateTime.now().weekday).index;
      if (day.index != todayIndex) return false; // only today can be locked
      int? mins(String hhmm) {
        final p = hhmm.split(':');
        if (p.length < 2) return null;
        final h = int.tryParse(p[0]);
        final m = int.tryParse(p[1]);
        return (h == null || m == null) ? null : h * 60 + m;
      }

      final open = mins(displayOpen);
      final close = mins(displayClose);
      if (open == null || close == null) return false;
      final now = TimeOfDay.now();
      final nowM = now.hour * 60 + now.minute;
      return nowM >= open && nowM <= close;
    }

    final priceLocked = computePriceLocked();

    final cardBg = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isEnabled
        ? AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.25)
        : (isDark ? AppColors.borderDark : AppColors.border);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: borderColor, width: isEnabled ? 1.5 : 1.0),
        boxShadow: isEnabled && !isDark
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ─────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    MealModel.slotIcon(meal.slotKey),
                    size: 20,
                    color: isEnabled
                        ? AppColors.primary
                        : (isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: AppConstants.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: AppTypography.titleSmall.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (isDark
                                  ? AppColors.borderDark
                                  : AppColors.border)
                              .withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 12,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                TimeFormat.window12(displayOpen, displayClose),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySmall.copyWith(
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isEnabled && dayEntry!.hasCustomTiming) ...[
                              const SizedBox(width: 5),
                              const Icon(
                                Icons.timer_outlined,
                                size: 11,
                                color: AppColors.secondary,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Edit button (only when enabled and not read-only)
                if (onEdit != null)
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    tooltip: 'Edit this day only',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                // Toggle or read-only dot
                if (readOnly)
                  _StatusDot(isEnabled: isEnabled)
                else
                  Switch(
                    value: isEnabled,
                    onChanged: onToggle,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
              ],
            ),

            // Divider before status + items
            if (isEnabled || displayItems.isNotEmpty) ...[
              const SizedBox(height: AppConstants.space12),
              const Divider(height: 1),
              const SizedBox(height: AppConstants.space12),
            ],

            // Enabled / disabled status badge
            Row(
              children: [
                _StatusLabel(isEnabled: isEnabled, isDark: isDark),
                if (displayPrice != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    '₹$displayPrice',
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  if (priceLocked) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.lock_rounded,
                      size: 12,
                      color: AppColors.primary.withValues(alpha: 0.7),
                    ),
                  ],
                ],
                if (displayItems.isNotEmpty) ...[
                  const Spacer(),
                  Text(
                    '${displayItems.length} item'
                    '${displayItems.length == 1 ? '' : 's'}',
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),

            // Menu items preview
            if (displayItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MenuItemsPreview(
                items: displayItems,
                isDark: isDark,
                isEnabled: isEnabled,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Status label ───────────────────────────────────────────────────────────────

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.isEnabled, required this.isDark});
  final bool isEnabled;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final color = isEnabled
        ? AppColors.present
        : (isDark ? AppColors.textSecondaryDark : AppColors.textTertiary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isEnabled
            ? AppColors.present.withValues(alpha: 0.12)
            : (isDark
                ? AppColors.borderDark.withValues(alpha: 0.4)
                : AppColors.border.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            isEnabled ? 'Enabled this day' : 'Disabled this day',
            style: AppTypography.labelSmall.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status dot (preview/read-only) ────────────────────────────────────────────

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.isEnabled});
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isEnabled
            ? AppColors.present.withValues(alpha: 0.15)
            : AppColors.absent.withValues(alpha: 0.10),
      ),
      child: Icon(
        isEnabled ? Icons.check_rounded : Icons.close_rounded,
        size: 14,
        color: isEnabled ? AppColors.present : AppColors.absent,
      ),
    );
  }
}

// ── Menu items preview ─────────────────────────────────────────────────────────

class _MenuItemsPreview extends StatefulWidget {
  const _MenuItemsPreview({
    required this.items,
    required this.isDark,
    required this.isEnabled,
  });

  final List<String> items;
  final bool isDark;
  final bool isEnabled;

  @override
  State<_MenuItemsPreview> createState() => _MenuItemsPreviewState();
}

class _MenuItemsPreviewState extends State<_MenuItemsPreview> {
  static const _maxVisible = 4;

  // Issue 3: tapping "+X more" expands to show every item (and "Show less"
  // collapses again). Previously the chip was inert.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final items = widget.items;
    final visible =
        _expanded ? items : items.take(_maxVisible).toList();
    final overflow = items.length - items.take(_maxVisible).length;

    final chipBg = isDark
        ? AppColors.surfaceVariantDark
        : AppColors.primary.withValues(alpha: 0.07);
    final chipFg =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visible.map(
          (item) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: chipBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? AppColors.borderDark
                    : AppColors.border.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              item,
              style: AppTypography.labelSmall.copyWith(
                fontSize: 11,
                color: chipFg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (overflow > 0)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _expanded ? 'Show less' : '+$overflow more',
                style: AppTypography.labelSmall.copyWith(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Multi-preference groups (read-only, premium tags) ───────────────────────

/// #3: shows a meal's master-level multi-preference groups inside the weekly
/// editor as premium, responsive tag chips. Read-only here because groups are
/// master-level (FR-PG-*) and apply to EVERY day the meal runs — per-day
/// overrides exist only for the legacy flat single-preference.
class _MultiPrefGroupsCard extends StatelessWidget {
  const _MultiPrefGroupsCard({
    required this.groups,
    required this.isDark,
    required this.selectedIds,
    required this.onToggle,
    this.enabled = true,
  });

  final List<PreferenceGroupModel> groups;
  final bool isDark;

  /// #3: whether preferences are enabled for THIS day. When false the card
  /// shows an "Off this day" state (the backend also hides the groups).
  final bool enabled;

  /// #3: the group ids currently active for this day (checkbox state).
  final Set<String> selectedIds;

  /// #3: toggle a group on/off for this day.
  final void Function(String groupId, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: isDark ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Multi-preference groups',
                  style: AppTypography.labelMedium.copyWith(
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (enabled ? AppColors.primary : AppColors.textTertiary)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  enabled ? 'Applies every day' : 'Off this day',
                  style: AppTypography.labelSmall.copyWith(
                    color:
                        enabled ? AppColors.primary : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            enabled
                ? 'Tick the groups that apply THIS day (defined in Master Meal '
                    'Template). Unticked groups are hidden for this day only.'
                : "Preferences are OFF for this day — members won't pick any "
                    'option. Turn the toggle on to use these groups.',
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ...groups.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // #3: include/exclude this group for THIS day only.
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: selectedIds.contains(g.id),
                            onChanged: enabled
                                ? (v) => onToggle(g.id, v ?? false)
                                : null,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            g.label,
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceVariantDark
                                : AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            g.ruleLabel,
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Responsive: chips wrap to as many rows as needed.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: g.options.map((o) {
                        final priceAdd = o.priceDelta > 0
                            ? ' +₹${(o.priceDelta / 100).toStringAsFixed(o.priceDelta % 100 == 0 ? 0 : 2)}'
                            : '';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                isDark ? AppColors.surfaceDark : AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Text(
                            '${o.displayLabel}$priceAdd',
                            style: AppTypography.labelSmall.copyWith(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ── Per-day meal edit sheet ────────────────────────────────────────────────────

/// Bottom sheet that lets the admin edit a single day's [DayMealEntry].
///
/// **Independence guarantee**: changes call [onSave] which routes to
/// [MealConfigProvider.updateDayMealEntry].  That method touches ONLY the
/// supplied [day] + [mealId] entry — every other day remains unchanged.
class _DayMealEditSheet extends StatefulWidget {
  const _DayMealEditSheet({
    required this.day,
    required this.entry,
    required this.templateName,
    required this.templateMenuItems,
    this.templateDescription,
    required this.templateOpenTime,
    required this.templateCloseTime,
    required this.templatePreferenceOptions,
    required this.templatePreferenceGroups,
    required this.pricingEnabled,
    this.templatePrice,
    required this.onSave,
  });

  final DayOfWeek day;
  final DayMealEntry entry;
  final String templateName;
  final List<String> templateMenuItems;

  /// Master meal description used as the placeholder / inherited default.
  final String? templateDescription;
  final String templateOpenTime;
  final String templateCloseTime;
  final List<String> templatePreferenceOptions;

  /// #3: master-level multi-preference groups (FR-PG-*). When non-empty the
  /// weekly editor shows them as premium read-only tags (they apply every day).
  final List<PreferenceGroupModel> templatePreferenceGroups;

  /// Additive: when true (group pricing ON), a per-day Price (₹) field shows.
  final bool pricingEnabled;

  /// Master meal price used as the placeholder when no per-day override is set.
  final int? templatePrice;

  final void Function({
    required String name,
    required List<String> menuItems,
    String? description,
    List<Uint8List>? imageBytes,
    String? openTime,
    String? closeTime,
    required bool preferencesEnabled,
    required List<String> enabledPreferences,
    required List<String> enabledPreferenceGroupIds,
    int? price,
  }) onSave;

  @override
  State<_DayMealEditSheet> createState() => _DayMealEditSheetState();
}

class _DayMealEditSheetState extends State<_DayMealEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _itemCtrl;
  late final TextEditingController _openCtrl;
  late final TextEditingController _closeCtrl;
  late final TextEditingController _priceCtrl;
  late List<String> _menuItems;
  bool _useCustomTiming = false;
  bool _prefsEnabled = false;
  late List<String> _selectedPrefs;
  // #3: per-day subset of master preference group ids that apply this day.
  late Set<String> _selectedGroupIds;

  // Per-day photo (max 1, ≤100 KB) — mirrors the master meal editor.
  late List<Uint8List> _imageBytes;
  bool _isPickingImage = false;
  String? _imageError;

  // Stored values stay strict 24-hour "HH:mm" (backend contract). The visible
  // controllers show the AM/PM label only — saving reads these vars, never the
  // controller text, so the contract is preserved.
  late String _openHHmm;
  late String _closeHHmm;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _descCtrl = TextEditingController(
      text: widget.entry.description ?? '',
    );
    // Preload this entry's OWN per-day photo (decoded from its imageUrl data
    // URI). Empty = no per-day override → the meal inherits the master photo.
    final existing = widget.entry.displayImageBytes;
    _imageBytes = existing != null ? <Uint8List>[existing] : <Uint8List>[];
    _itemCtrl = TextEditingController();
    _useCustomTiming = widget.entry.hasCustomTiming;
    _openHHmm = widget.entry.openTime ?? widget.templateOpenTime;
    _closeHHmm = widget.entry.closeTime ?? widget.templateCloseTime;
    _openCtrl = TextEditingController(text: TimeFormat.hm12(_openHHmm));
    _closeCtrl = TextEditingController(text: TimeFormat.hm12(_closeHHmm));
    _menuItems = List<String>.from(widget.entry.menuItems);
    _prefsEnabled = widget.entry.preferencesEnabled;
    _selectedPrefs = List<String>.from(widget.entry.enabledPreferences);
    // #3: per-day group subset. An empty saved value means "inherit ALL", so
    // start with every master group checked; the admin unchecks to narrow.
    _selectedGroupIds = widget.entry.enabledPreferenceGroupIds.isNotEmpty
        ? widget.entry.enabledPreferenceGroupIds.toSet()
        : widget.templatePreferenceGroups.map((g) => g.id).toSet();
    _priceCtrl = TextEditingController(
      text: widget.entry.price?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _itemCtrl.dispose();
    _openCtrl.dispose();
    _closeCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  /// Pick a single photo and compress to ≤100 KB (replaces any existing).
  /// Mirrors the master meal editor's behaviour exactly.
  Future<void> _pickImage() async {
    setState(() {
      _isPickingImage = true;
      _imageError = null;
    });
    try {
      final file =
          await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) {
        setState(() => _isPickingImage = false);
        return;
      }
      final raw = await file.readAsBytes();
      Uint8List? out;
      for (final q in const [70, 55, 40, 30, 20]) {
        final c = await FlutterImageCompress.compressWithList(
          raw,
          quality: q,
          minWidth: 1080,
          minHeight: 720,
          format: CompressFormat.jpeg,
          keepExif: false,
        );
        if (c.isEmpty) continue;
        out = c;
        if (c.length <= AppConstants.maxMealImageBytes) break;
      }
      if (out == null || out.isEmpty) {
        setState(() => _imageError = 'Could not process this photo.');
        return;
      }
      if (out.length > AppConstants.maxMealImageBytes) {
        setState(() => _imageError =
            'Photo too large even after compression (limit '
            '${AppConstants.maxMealImageBytes ~/ 1024} KB).');
        return;
      }
      setState(() => _imageBytes = [out!]);
    } catch (_) {
      setState(() => _imageError = 'Could not pick the photo.');
    } finally {
      setState(() => _isPickingImage = false);
    }
  }

  void _addItem() {
    final val = _itemCtrl.text.trim();
    if (val.isEmpty) return;
    setState(() {
      _menuItems.add(val);
      _itemCtrl.clear();
    });
  }

  void _removeItem(int index) {
    setState(() => _menuItems.removeAt(index));
  }

  /// Issue 9: parse an "HH:mm" string into a [TimeOfDay], or null if invalid.
  TimeOfDay? _timeOfDayFromHHmm(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  /// Open a Material time picker (AM/PM dial) and store the chosen time as a
  /// strict "HH:mm" value, while showing the AM/PM label in the field.
  Future<void> _pickTime({required bool isOpen}) async {
    final current = isOpen ? _openHHmm : _closeHHmm;
    final initial = _timeOfDayFromHHmm(current) ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: forceAmPmTimePicker,
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    setState(() {
      if (isOpen) {
        _openHHmm = '$hh:$mm';
        _openCtrl.text = TimeFormat.hm12(_openHHmm);
      } else {
        _closeHHmm = '$hh:$mm';
        _closeCtrl.text = TimeFormat.hm12(_closeHHmm);
      }
    });
  }

  /// Display label for a lowercase preference key (e.g. "veg" -> "Veg").
  String _prefLabel(String key) =>
      key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  /// Per-day price is locked ONLY for TODAY while its attendance window is
  /// currently open (open ≤ now ≤ close). Past weekdays, future weekdays, today
  /// before open, and today after close stay editable — those edits apply to
  /// the next occurrence of that weekday, never to a completed day.
  bool get _priceLocked {
    if (!widget.pricingEnabled) return false;
    final todayIndex = DayOfWeek.fromWeekday(DateTime.now().weekday).index;
    if (widget.day.index != todayIndex) return false;
    int? mins(String hhmm) {
      final p = hhmm.split(':');
      if (p.length < 2) return null;
      final h = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      return (h == null || m == null) ? null : h * 60 + m;
    }

    final open = mins(widget.entry.openTime ?? widget.templateOpenTime);
    final close = mins(widget.entry.closeTime ?? widget.templateCloseTime);
    if (open == null || close == null) return false;
    final now = TimeOfDay.now();
    final nowM = now.hour * 60 + now.minute;
    return nowM >= open && nowM <= close;
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final desc = _descCtrl.text.trim();
    widget.onSave(
      name: name,
      menuItems: List<String>.from(_menuItems),
      description: desc.isEmpty ? null : desc,
      imageBytes: List<Uint8List>.from(_imageBytes),
      openTime: _useCustomTiming ? _openHHmm : null,
      closeTime: _useCustomTiming ? _closeHHmm : null,
      preferencesEnabled: _prefsEnabled,
      enabledPreferences:
          _prefsEnabled ? List<String>.from(_selectedPrefs) : <String>[],
      // #3: save the per-day group subset. All selected = save empty (inherit
      // ALL, future-proof if a new master group is added); else the subset.
      enabledPreferenceGroupIds: !_prefsEnabled
          ? <String>[]
          : (_selectedGroupIds.length >= widget.templatePreferenceGroups.length
              ? <String>[]
              : _selectedGroupIds.toList()),
      // Issue 2: when locked, never let the current day's price change.
      price: widget.pricingEnabled
          ? (_priceLocked
              ? widget.entry.price
              : int.tryParse(_priceCtrl.text.trim()))
          : widget.entry.price,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.bottomSheetRadius),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit ${widget.day.fullLabel}',
                        style: AppTypography.titleMedium.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Changes affect only ${widget.day.fullLabel} — other days unchanged.',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Meal name override ───────────────────────────────────────────
            Text(
              'Meal name for this day',
              style: AppTypography.labelMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: widget.templateName,
                helperText:
                    'Template: "${widget.templateName}"',
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.inputRadius),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Description (parity with master meal config) ─────────────────
            Text(
              'Description for this day',
              style: AppTypography.labelMedium.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descCtrl,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: widget.templateDescription?.isNotEmpty == true
                    ? widget.templateDescription
                    : 'Optional — describe this day’s meal',
                helperText: 'Leave blank to inherit the master description.',
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.inputRadius),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Photo (1 only, ≤100 KB) — parity with master meal config ─────
            _DayPhotoField(
              imageBytes: _imageBytes,
              isPicking: _isPickingImage,
              error: _imageError,
              onPick: _pickImage,
              onRemove: () => setState(() {
                _imageBytes = const [];
                _imageError = null;
              }),
              isDark: isDark,
            ),
            const SizedBox(height: 16),

            // ── Custom timing toggle ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Custom time window for this day',
                    style: AppTypography.labelMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: _useCustomTiming,
                  onChanged: (v) => setState(() => _useCustomTiming = v),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.primary,
                ),
              ],
            ),
            if (_useCustomTiming) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _openCtrl,
                      readOnly: true,
                      onTap: () => _pickTime(isOpen: true),
                      decoration: InputDecoration(
                        labelText: 'Open time',
                        hintText: widget.templateOpenTime,
                        suffixIcon:
                            const Icon(Icons.schedule_rounded, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.inputRadius),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _closeCtrl,
                      readOnly: true,
                      onTap: () => _pickTime(isOpen: false),
                      decoration: InputDecoration(
                        labelText: 'Close time',
                        hintText: widget.templateCloseTime,
                        suffixIcon:
                            const Icon(Icons.schedule_rounded, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              AppConstants.inputRadius),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // ── Menu items ───────────────────────────────────────────────────
            Text(
              'Menu items for this day',
              style: AppTypography.labelMedium.copyWith(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Completely independent from other days.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),

            // Add item row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemCtrl,
                    onSubmitted: (_) => _addItem(),
                    decoration: InputDecoration(
                      hintText: 'Add menu item',
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.inputRadius),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addItem,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Add'),
                ),
              ],
            ),

            if (_menuItems.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _menuItems.asMap().entries.map((e) {
                  final chipBg = isDark
                      ? AppColors.surfaceVariantDark
                      : AppColors.primary.withValues(alpha: 0.08);
                  final chipFg = isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary;
                  return Container(
                    padding: const EdgeInsets.only(
                        left: 10, right: 4, top: 4, bottom: 4),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? AppColors.borderDark
                            : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          e.value,
                          style: AppTypography.labelSmall.copyWith(
                            fontSize: 12,
                            color: chipFg,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _removeItem(e.key),
                          child: Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: chipFg.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 16),

            // ── Per-day price (when group pricing enabled) ───────────────────
            if (widget.pricingEnabled) ...[
              Text(
                'Price for this day (₹)',
                style: AppTypography.labelMedium.copyWith(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _priceCtrl,
                enabled: !_priceLocked,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  suffixIcon: _priceLocked
                      ? const Icon(Icons.lock_rounded,
                          size: 18, color: AppColors.textTertiary)
                      : null,
                  hintText: widget.templatePrice != null
                      ? 'Default ₹${widget.templatePrice}'
                      : 'e.g. 40',
                  helperText: _priceLocked
                      ? 'Price locked while attendance is open. Editable once the window closes.'
                      : 'Leave blank to inherit the master meal price.',
                  helperStyle: _priceLocked
                      ? const TextStyle(color: AppColors.warning)
                      : null,
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.inputRadius),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Per-day meal preference (#6) ─────────────────────────────────
            // #3: meals configured with MULTI-preference groups (master-level,
            // FR-PG-*) surface them here as premium read-only tags. The flat
            // per-day toggle below only applies to legacy single-tag meals.
            if (widget.templatePreferenceGroups.isNotEmpty) ...[
              // #3: per-day enable toggle — turning this OFF hides the meal's
              // multi-preference groups for THIS day (the backend gates it too,
              // so members pick nothing that day). Master config is untouched.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Meal preferences this day',
                      style: AppTypography.labelMedium.copyWith(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: _prefsEnabled,
                    onChanged: (v) => setState(() => _prefsEnabled = v),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _MultiPrefGroupsCard(
                groups: widget.templatePreferenceGroups,
                isDark: isDark,
                enabled: _prefsEnabled,
                selectedIds: _selectedGroupIds,
                onToggle: (id, sel) => setState(() {
                  if (sel) {
                    _selectedGroupIds.add(id);
                  } else {
                    _selectedGroupIds.remove(id);
                  }
                }),
              ),
            ] else ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Meal preferences this day',
                    style: AppTypography.labelMedium.copyWith(
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Switch(
                  value: _prefsEnabled,
                  onChanged: (v) => setState(() => _prefsEnabled = v),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.primary,
                ),
              ],
            ),
            if (_prefsEnabled) ...[
              const SizedBox(height: 4),
              Text(
                'Independent from other days. Choose which tags members pick.',
                style: AppTypography.bodySmall.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.templatePreferenceOptions.map((opt) {
                  final selected = _selectedPrefs.contains(opt);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _selectedPrefs.remove(opt);
                      } else {
                        _selectedPrefs.add(opt);
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : (isDark
                                ? AppColors.surfaceVariantDark
                                : AppColors.surfaceVariant),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.borderDark
                                  : AppColors.border),
                        ),
                      ),
                      child: Text(
                        _prefLabel(opt),
                        style: AppTypography.labelSmall.copyWith(
                          fontSize: 12,
                          color: selected
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            ],
            const SizedBox(height: 20),

            // ── Save button ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppConstants.buttonRadius),
                  ),
                ),
                child: Text(
                  'Save ${widget.day.fullLabel} Changes',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Per-day photo field ─────────────────────────────────────────────────────

/// Single-photo (≤100 KB) picker for the per-day meal editor. Mirrors the
/// master meal config image rule: exactly one photo, replaced on each upload.
class _DayPhotoField extends StatelessWidget {
  const _DayPhotoField({
    required this.imageBytes,
    required this.isPicking,
    required this.error,
    required this.onPick,
    required this.onRemove,
    required this.isDark,
  });

  final List<Uint8List> imageBytes;
  final bool isPicking;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final bool isDark;

  String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

  @override
  Widget build(BuildContext context) {
    final hasImage = imageBytes.isNotEmpty;
    final border = isDark ? AppColors.borderDark : AppColors.border;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Meal photo for this day',
                style: AppTypography.labelMedium.copyWith(
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '1 photo · 100 KB',
              style: AppTypography.labelSmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (isPicking)
          Container(
            height: 64,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (hasImage)
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  imageBytes.first,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _kb(imageBytes.first.length),
                  style: AppTypography.labelSmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textTertiary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Replace'),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                color: AppColors.error,
                tooltip: 'Remove photo',
              ),
            ],
          )
        else
          GestureDetector(
            onTap: onPick,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 18,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to add photo',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 6),
          Text(
            error!,
            style: AppTypography.labelSmall.copyWith(color: AppColors.error),
          ),
        ],
      ],
    );
  }
}

// ── Enum ─────────────────────────────────────────────────────────

/// Horizontal group chips so the admin can pick which group's weekly schedule
/// to edit — mirrors the Meal Config selector. Additive (Issue 1).
class _PlannerGroupSelector extends StatelessWidget {
  const _PlannerGroupSelector({
    required this.groups,
    required this.selectedId,
    required this.onSelect,
  });

  final List<GroupModel> groups;
  final String? selectedId;
  final Future<void> Function(GroupModel) onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: groups.map((g) {
            final selected = g.id == selectedId;
            return GestureDetector(
              onTap: () => onSelect(g),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : colorScheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  g.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : null,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

enum _ScheduleAction {
  copyPrevious,
  revertToDraft,
  unpublishHide,
  toggleRecurring,
}

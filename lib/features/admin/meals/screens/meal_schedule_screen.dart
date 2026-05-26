import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/admin/meals/providers/meal_config_provider.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
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
  const MealScheduleScreen({super.key});

  @override
  State<MealScheduleScreen> createState() => _MealScheduleScreenState();
}

class _MealScheduleScreenState extends State<MealScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final MealConfigProvider _provider;
  late final TabController _tabController;
  bool _initialized = false;
  bool _previewMode = false;

  static const _days = DayOfWeek.values;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _days.length, vsync: this);
    _tabController.index = DayOfWeek.fromWeekday(DateTime.now().weekday).index;
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
      if (user == null) return;
      final orgId = user.organizationId;
      _provider.loadGroups(organizationId: orgId).then((_) {
        if (_provider.selectedGroup != null) {
          _provider.loadSchedule(
            organizationId: orgId,
            groupId: _provider.selectedGroup!.id,
          );
        }
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
        templateOpenTime: template.attendanceWindow.openTime,
        templateCloseTime: template.attendanceWindow.closeTime,
        onSave: ({
          required String name,
          required List<String> menuItems,
          String? openTime,
          String? closeTime,
        }) {
          _provider.updateDayMealEntry(
            day,
            mealId,
            name: name,
            menuItems: menuItems,
            openTime: openTime,
            closeTime: closeTime,
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
                _provider.isSaving ? 'Publishing…' : 'Publish Schedule',
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
            Text('Weekly Planner', style: AppTypography.titleLarge),
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
          PopupMenuButton<_ScheduleAction>(
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (_) => [
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
              if (isPublished)
                const PopupMenuItem(
                  enabled: false,
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.present),
                      SizedBox(width: 10),
                      Text('Published'),
                    ],
                  ),
                ),
            ],
            onSelected: (action) {
              switch (action) {
                case _ScheduleAction.copyPrevious:
                  _copyFromPreviousWeek();
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
          tabs: _days.map((d) {
            final isToday = d == today;
            return Tab(
              height: 40,
              child: Text(
                d.label,
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
      body: _provider.isLoading
          ? const AppLoadingIndicator()
          : _provider.weekSchedule == null
              ? const AppEmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'No schedule yet',
                  subtitle:
                      'Configure meals first, then build your weekly schedule here.',
                )
              : Column(
                  children: [
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
    this.onToggle,
    this.onEdit,
  });

  final MealModel meal;

  /// Day-specific entry.  Non-null when this meal is enabled for the day.
  final DayMealEntry? dayEntry;
  final bool isEnabled;
  final bool readOnly;
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
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$displayOpen – $displayClose',
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (isEnabled && dayEntry!.hasCustomTiming) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.timer_outlined,
                              size: 11,
                              color: AppColors.secondary,
                            ),
                          ],
                        ],
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

class _MenuItemsPreview extends StatelessWidget {
  const _MenuItemsPreview({
    required this.items,
    required this.isDark,
    required this.isEnabled,
  });

  final List<String> items;
  final bool isDark;
  final bool isEnabled;

  static const _maxVisible = 4;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(_maxVisible).toList();
    final overflow = items.length - visible.length;

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '+$overflow more',
              style: AppTypography.labelSmall.copyWith(
                fontSize: 11,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
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
    required this.templateOpenTime,
    required this.templateCloseTime,
    required this.onSave,
  });

  final DayOfWeek day;
  final DayMealEntry entry;
  final String templateName;
  final List<String> templateMenuItems;
  final String templateOpenTime;
  final String templateCloseTime;
  final void Function({
    required String name,
    required List<String> menuItems,
    String? openTime,
    String? closeTime,
  }) onSave;

  @override
  State<_DayMealEditSheet> createState() => _DayMealEditSheetState();
}

class _DayMealEditSheetState extends State<_DayMealEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _itemCtrl;
  late final TextEditingController _openCtrl;
  late final TextEditingController _closeCtrl;
  late List<String> _menuItems;
  bool _useCustomTiming = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _itemCtrl = TextEditingController();
    _useCustomTiming = widget.entry.hasCustomTiming;
    _openCtrl = TextEditingController(
      text: widget.entry.openTime ?? widget.templateOpenTime,
    );
    _closeCtrl = TextEditingController(
      text: widget.entry.closeTime ?? widget.templateCloseTime,
    );
    _menuItems = List<String>.from(widget.entry.menuItems);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _itemCtrl.dispose();
    _openCtrl.dispose();
    _closeCtrl.dispose();
    super.dispose();
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

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    widget.onSave(
      name: name,
      menuItems: List<String>.from(_menuItems),
      openTime: _useCustomTiming ? _openCtrl.text.trim() : null,
      closeTime: _useCustomTiming ? _closeCtrl.text.trim() : null,
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
                      decoration: InputDecoration(
                        labelText: 'Open time',
                        hintText: widget.templateOpenTime,
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
                      decoration: InputDecoration(
                        labelText: 'Close time',
                        hintText: widget.templateCloseTime,
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

// ── Enum ─────────────────────────────────────────────────────────

enum _ScheduleAction { copyPrevious }

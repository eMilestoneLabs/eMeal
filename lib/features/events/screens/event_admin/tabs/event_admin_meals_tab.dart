import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/core/theme/app_typography.dart';
import 'package:smart_meal_management/features/events/models/event_meal_type.dart';
import 'package:smart_meal_management/features/events/providers/event_admin_provider.dart';
import 'package:smart_meal_management/features/events/screens/event_admin/event_admin_shell.dart';

// ── EventAdminMealsTab ─────────────────────────────────────────────────────────

/// Meals tab — admin dynamically creates, edits, and removes meal types.
///
/// Replaces the old static 3-toggle approach. Admins define any set of meal
/// types (Veg, Jain, Chicken, Custom…) with a title, emoji, color, and
/// veg/non-veg flag. Guests see exactly these options when selecting meals.
class EventAdminMealsTab extends StatelessWidget {
  const EventAdminMealsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = EventAdminScope.of(context);
    final event = provider.event;
    final isDark = EventThemeScope.isDark(context);

    if (event == null) return const SizedBox.shrink();

    final mealTypes = event.mealTypes;
    final breakdown = provider.mealTypeBreakdown;

    return CustomScrollView(
      slivers: [
        // ── App bar ─────────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          automaticallyImplyLeading: false,
          backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              const Icon(Icons.restaurant_menu_rounded,
                  size: 20, color: AppColors.vacation),
              const SizedBox(width: 10),
              Text(
                'Meal Types',
                style: AppTypography.titleLarge.copyWith(
                  color:
                      isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${mealTypes.length} configured',
                style: AppTypography.labelSmall.copyWith(
                  color: isDark
                      ? AppColors.textTertiaryDark
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),

        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppConstants.pagePaddingH,
            20,
            AppConstants.pagePaddingH,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── Info card ────────────────────────────────────────────────
              _InfoBanner(isDark: isDark),
              const SizedBox(height: 24),

              // ── Current meal types ───────────────────────────────────────
              _SectionHeader(
                title: 'Configured Meal Types',
                isDark: isDark,
              ),
              const SizedBox(height: 12),

              if (mealTypes.isEmpty)
                _EmptyMealTypesCard(isDark: isDark)
              else ...[
                ...mealTypes.map((mealType) {
                  final stats = breakdown[mealType.id];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MealTypeTile(
                      mealType: mealType,
                      stats: stats,
                      isDark: isDark,
                      onDelete: () =>
                          _confirmDelete(context, provider, mealType, isDark),
                      onEdit: () =>
                          _showEditSheet(context, provider, mealType, isDark),
                    ),
                  );
                }),
                const SizedBox(height: 8),

                // ── Aggregate stats ──────────────────────────────────────
                _AggregateStats(provider: provider, isDark: isDark),
                const SizedBox(height: 24),
              ],

              // ── Add meal type button ─────────────────────────────────────
              _AddMealTypeButton(
                isDark: isDark,
                existingTypes: mealTypes,
                onAdd: (mealType) => provider.addMealType(mealType),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(
    BuildContext context,
    EventAdminProvider provider,
    EventMealType mealType,
    bool isDark,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius)),
        title: Text(
          'Remove ${mealType.title}?',
          style: AppTypography.titleMedium.copyWith(
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Guests who selected this meal type will show as pending. This cannot be undone.',
          style: AppTypography.bodySmall.copyWith(
            color:
                isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppTypography.bodySmall.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await provider.removeMealType(mealType.id);
    }
  }

  Future<void> _showEditSheet(
    BuildContext context,
    EventAdminProvider provider,
    EventMealType mealType,
    bool isDark,
  ) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MealTypeFormSheet(
        isDark: isDark,
        existingTypes: provider.event?.mealTypes ?? [],
        initialValue: mealType,
        onSave: (updated) => provider.updateMealType(updated),
      ),
    );
  }
}

// ── Info banner ────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            AppColors.vacation.withValues(alpha: isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border:
            Border.all(color: AppColors.vacation.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 16, color: AppColors.vacation),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Create your own meal types — name them anything you like (Chicken, '
              'Jain, Dessert, Custom…). Guests will choose from exactly these options.',
              style: AppTypography.bodySmall.copyWith(
                color:
                    isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.isDark});
  final String title;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: AppTypography.titleSmall.copyWith(
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyMealTypesCard extends StatelessWidget {
  const _EmptyMealTypesCard({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark.withValues(alpha: 0.5)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.4)
              : AppColors.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          const Text(
            '🍽',
            style: TextStyle(fontSize: 40),
          ),
          const SizedBox(height: 12),
          Text(
            'No meal types yet',
            style: AppTypography.titleSmall.copyWith(
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add meal types so guests can choose when joining your event.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Meal type tile ─────────────────────────────────────────────────────────────

class _MealTypeTile extends StatelessWidget {
  const _MealTypeTile({
    required this.mealType,
    required this.stats,
    required this.isDark,
    required this.onDelete,
    required this.onEdit,
  });

  final EventMealType mealType;
  final ({int total, int adults, int children})? stats;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final total = stats?.total ?? 0;
    final adults = stats?.adults ?? 0;
    final children = stats?.children ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: mealType.color.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: mealType.color.withValues(alpha: isDark ? 0.05 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header row ────────────────────────────────────────────────
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                // Color dot
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: mealType.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                // Emoji
                Text(mealType.emoji,
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mealType.title,
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: mealType.isVeg
                              ? const Color(0xFF4CAF50).withValues(alpha: 0.12)
                              : const Color(0xFFFF5722).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          mealType.isVeg ? '🟢 Veg' : '🔴 Non-Veg',
                          style: AppTypography.labelSmall.copyWith(
                            fontSize: 10,
                            color: mealType.isVeg
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFF5722),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Actions
                IconButton(
                  icon: Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: isDark
                        ? AppColors.textTertiaryDark
                        : AppColors.textTertiary,
                  ),
                  onPressed: onEdit,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.error),
                  onPressed: onDelete,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          // ── Stats row ─────────────────────────────────────────────────
          if (total > 0) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: isDark
                  ? AppColors.borderDark.withValues(alpha: 0.3)
                  : AppColors.border.withValues(alpha: 0.6),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _StatChip(
                    label: 'Total',
                    value: total,
                    color: mealType.color,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Adults',
                    value: adults,
                    color: mealType.color.withValues(alpha: 0.7),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Children',
                    value: children,
                    color: mealType.color.withValues(alpha: 0.55),
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ] else ...[
            Divider(
              height: 1,
              thickness: 1,
              color: isDark
                  ? AppColors.borderDark.withValues(alpha: 0.3)
                  : AppColors.border.withValues(alpha: 0.6),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded,
                      size: 14,
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary),
                  const SizedBox(width: 6),
                  Text(
                    'No guests have selected this meal type yet',
                    style: AppTypography.labelSmall.copyWith(
                      color: isDark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Stat chip ──────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final String label;
  final int value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: AppTypography.labelSmall.copyWith(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              fontSize: 10,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Aggregate stats ────────────────────────────────────────────────────────────

class _AggregateStats extends StatelessWidget {
  const _AggregateStats(
      {required this.provider, required this.isDark});

  final EventAdminProvider provider;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.backgroundDark.withValues(alpha: 0.6)
            : AppColors.background,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderDark.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aggregate Summary',
            style: AppTypography.labelSmall.copyWith(
              color:
                  isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _AggregatePill(
                emoji: '🟢',
                label: 'Veg',
                value: provider.totalVegCount,
                color: const Color(0xFF4CAF50),
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              _AggregatePill(
                emoji: '🔴',
                label: 'Non-Veg',
                value: provider.totalNonVegCount,
                color: const Color(0xFFFF5722),
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              _AggregatePill(
                emoji: '⏳',
                label: 'Pending',
                value: provider.pendingMealCount,
                color: AppColors.warning,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AggregatePill extends StatelessWidget {
  const _AggregatePill({
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
    required this.isDark,
  });

  final String emoji;
  final String label;
  final int value;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              '$value',
              style: AppTypography.titleSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                fontSize: 10,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add meal type button ───────────────────────────────────────────────────────

class _AddMealTypeButton extends StatelessWidget {
  const _AddMealTypeButton({
    required this.isDark,
    required this.existingTypes,
    required this.onAdd,
  });

  final bool isDark;
  final List<EventMealType> existingTypes;
  final ValueChanged<EventMealType> onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _MealTypeFormSheet(
            isDark: isDark,
            existingTypes: existingTypes,
            initialValue: null,
            onSave: onAdd,
          ),
        ),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text('Add Meal Type'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.vacation,
          side: BorderSide(color: AppColors.vacation.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          ),
          textStyle: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Meal type form sheet ───────────────────────────────────────────────────────

/// Bottom sheet for adding a new meal type or editing an existing one.
///
/// Two modes:
///   1. **Presets picker** — tap a preset to add instantly
///   2. **Custom form** — enter title, choose emoji + color + veg flag
class _MealTypeFormSheet extends StatefulWidget {
  const _MealTypeFormSheet({
    required this.isDark,
    required this.existingTypes,
    required this.initialValue,
    required this.onSave,
  });

  final bool isDark;
  final List<EventMealType> existingTypes;
  final EventMealType? initialValue;
  final ValueChanged<EventMealType> onSave;

  @override
  State<_MealTypeFormSheet> createState() => _MealTypeFormSheetState();
}

class _MealTypeFormSheetState extends State<_MealTypeFormSheet> {
  late final TextEditingController _titleCtrl;
  late String _emoji;
  late Color _color;
  late bool _isVeg;
  // Open in custom-create mode by default.
  // The "Suggestions" tab still available for quick-add.
  bool _customMode = true;

  // Emoji options for picker
  static const List<String> _emojiOptions = [
    '🥗', '🙏', '🥚', '🍗', '🐟', '🍖', '🎂', '🥤',
    '🍛', '🍱', '🥘', '🍲', '🥙', '🌮', '🍜', '🧆',
    '🥩', '🍣', '🍤', '🥞', '🥗', '🥐', '🍰', '🧁',
  ];

  // Color palette for picker
  static const List<Color> _colorPalette = [
    Color(0xFF4CAF50), Color(0xFF8BC34A), Color(0xFFFFC107),
    Color(0xFFFF5722), Color(0xFF2196F3), Color(0xFF9C27B0),
    Color(0xFFE91E63), Color(0xFF00BCD4), Color(0xFFFF9800),
    Color(0xFF607D8B), Color(0xFF795548), Color(0xFF009688),
  ];

  @override
  void initState() {
    super.initState();
    final v = widget.initialValue;
    _titleCtrl = TextEditingController(text: v?.title ?? '');
    _emoji = v?.emoji ?? '🍽';
    _color = v?.color ?? _colorPalette.first;
    _isVeg = v?.isVeg ?? true;
    _customMode = v != null; // editing always starts in custom mode
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  // Available presets (filter out already-added ones by title match)
  List<EventMealType> get _availablePresets {
    final existingTitles =
        widget.existingTypes.map((e) => e.title.toLowerCase()).toSet();
    return EventMealType.presets
        .where((p) => !existingTitles.contains(p.title.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? AppColors.surfaceDark : AppColors.surface;
    final editing = widget.initialValue != null;

    return DraggableScrollableSheet(
      initialChildSize: _customMode ? 0.85 : 0.70,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Handle ──────────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.borderDark
                      : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── Title ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      editing
                          ? 'Edit Meal Type'
                          : (_customMode
                              ? 'Create Custom Meal Type'
                              : 'Add Meal Type'),
                      style: AppTypography.titleMedium.copyWith(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        size: 20,
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // ── Mode toggle (only for new types) ─────────────────────────
            if (!editing) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _ModeTab(
                      label: 'Custom',
                      isActive: _customMode,
                      isDark: isDark,
                      onTap: () => setState(() => _customMode = true),
                    ),
                    const SizedBox(width: 8),
                    _ModeTab(
                      label: 'Suggestions',
                      isActive: !_customMode,
                      isDark: isDark,
                      onTap: () => setState(() => _customMode = false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 8),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: controller,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  if (!_customMode && !editing)
                    _PresetsGrid(
                      presets: _availablePresets,
                      isDark: isDark,
                      onSelect: (preset) {
                        widget.onSave(preset);
                        Navigator.pop(context);
                      },
                      onCustom: () =>
                          setState(() => _customMode = true),
                    )
                  else
                    _CustomForm(
                      titleCtrl: _titleCtrl,
                      emoji: _emoji,
                      color: _color,
                      isVeg: _isVeg,
                      isDark: isDark,
                      emojiOptions: _emojiOptions,
                      colorPalette: _colorPalette,
                      onEmojiChanged: (e) => setState(() => _emoji = e),
                      onColorChanged: (c) => setState(() => _color = c),
                      onVegChanged: (v) => setState(() => _isVeg = v),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ── Save button (custom mode only) ───────────────────────────
            if (_customMode || editing) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    MediaQuery.paddingOf(context).bottom + 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.vacation,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppConstants.cardRadius),
                      ),
                    ),
                    child: Text(
                      editing ? 'Save Changes' : 'Add Meal Type',
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a meal type name')),
      );
      return;
    }
    final existing = widget.initialValue;
    final mealType = EventMealType(
      id: existing?.id ??
          'mt_${title.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      emoji: _emoji,
      color: _color,
      isVeg: _isVeg,
    );
    widget.onSave(mealType);
    Navigator.pop(context);
  }
}

// ── Mode tab ───────────────────────────────────────────────────────────────────

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.vacation
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppColors.vacation
                : (isDark
                    ? AppColors.borderDark
                    : AppColors.border),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: isActive
                ? Colors.white
                : (isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Presets grid ───────────────────────────────────────────────────────────────

class _PresetsGrid extends StatelessWidget {
  const _PresetsGrid({
    required this.presets,
    required this.isDark,
    required this.onSelect,
    required this.onCustom,
  });

  final List<EventMealType> presets;
  final bool isDark;
  final ValueChanged<EventMealType> onSelect;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) {
    if (presets.isEmpty) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'All preset types have been added.',
              style: AppTypography.bodySmall.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCustom,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create Custom Type'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.vacation,
                side:
                    BorderSide(color: AppColors.vacation.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suggested meal types — tap to add instantly',
          style: AppTypography.labelSmall.copyWith(
            color:
                isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (_, constraints) {
            // 3 columns with 10px gaps on a potentially narrow sheet
            final cardW = (constraints.maxWidth - 20) / 3;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: presets.map((preset) {
                return GestureDetector(
                  onTap: () => onSelect(preset),
                  child: SizedBox(
                    width: cardW,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.backgroundDark
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: preset.color.withValues(alpha: 0.35)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(preset.emoji,
                              style: const TextStyle(fontSize: 26)),
                          const SizedBox(height: 6),
                          Text(
                            preset.title,
                            style: AppTypography.bodySmall.copyWith(
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            preset.isVeg ? 'Veg' : 'Non-Veg',
                            style: AppTypography.labelSmall.copyWith(
                              fontSize: 9,
                              color: preset.isVeg
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF5722),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 20),
        Divider(
          color:
              isDark ? AppColors.borderDark : AppColors.border,
          height: 1,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onCustom,
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Create Custom Type'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.vacation,
              side:
                  BorderSide(color: AppColors.vacation.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppConstants.cardRadius)),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Custom form ────────────────────────────────────────────────────────────────

class _CustomForm extends StatelessWidget {
  const _CustomForm({
    required this.titleCtrl,
    required this.emoji,
    required this.color,
    required this.isVeg,
    required this.isDark,
    required this.emojiOptions,
    required this.colorPalette,
    required this.onEmojiChanged,
    required this.onColorChanged,
    required this.onVegChanged,
  });

  final TextEditingController titleCtrl;
  final String emoji;
  final Color color;
  final bool isVeg;
  final bool isDark;
  final List<String> emojiOptions;
  final List<Color> colorPalette;
  final ValueChanged<String> onEmojiChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<bool> onVegChanged;

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: isDark
          ? AppColors.backgroundDark.withValues(alpha: 0.5)
          : AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: isDark
                ? AppColors.borderDark.withValues(alpha: 0.6)
                : AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: AppColors.vacation, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      hintStyle: AppTypography.bodyMedium.copyWith(
        color:
            isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preview ──────────────────────────────────────────────────────
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 36)),
                const SizedBox(height: 6),
                Text(
                  titleCtrl.text.isEmpty ? 'Preview' : titleCtrl.text,
                  style: AppTypography.titleSmall.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Name field ───────────────────────────────────────────────────
        Text(
          'Meal Type Name',
          style: AppTypography.labelSmall.copyWith(
            color:
                isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: titleCtrl,
          style: AppTypography.bodyMedium.copyWith(
            color:
                isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
          decoration: inputDecoration.copyWith(
            hintText: 'e.g. Chicken, Jain, Dessert',
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),

        // ── Emoji picker ─────────────────────────────────────────────────
        Text(
          'Choose Emoji',
          style: AppTypography.labelSmall.copyWith(
            color:
                isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: emojiOptions.map((e) {
            final isSelected = e == emoji;
            return GestureDetector(
              onTap: () => onEmojiChanged(e),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.vacation.withValues(alpha: 0.15)
                      : (isDark
                          ? AppColors.backgroundDark
                          : AppColors.background),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.vacation
                        : (isDark
                            ? AppColors.borderDark.withValues(alpha: 0.5)
                            : AppColors.border),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 22))),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // ── Color picker ─────────────────────────────────────────────────
        Text(
          'Choose Color',
          style: AppTypography.labelSmall.copyWith(
            color:
                isDark ? AppColors.textTertiaryDark : AppColors.textTertiary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colorPalette.map((c) {
            final isSelected = c.toARGB32() == color.toARGB32();
            return GestureDetector(
              onTap: () => onColorChanged(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(
                          color: Colors.white,
                          width: 3,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        )
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: c.withValues(alpha: 0.5),
                            blurRadius: 6,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // ── Veg / Non-Veg toggle ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.backgroundDark.withValues(alpha: 0.4)
                : AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? AppColors.borderDark.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Text(
                isVeg ? '🟢' : '🔴',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVeg ? 'Vegetarian' : 'Non-Vegetarian',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Used for veg/non-veg analytics',
                      style: AppTypography.bodySmall.copyWith(
                        color: isDark
                            ? AppColors.textTertiaryDark
                            : AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isVeg,
                onChanged: onVegChanged,
                activeThumbColor: const Color(0xFF4CAF50),
                inactiveThumbColor: const Color(0xFFFF5722),
                inactiveTrackColor:
                    const Color(0xFFFF5722).withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:smart_meal_management/core/theme/app_colors.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';

/// Reusable 7×N operational scheduling grid.
///
/// Rows = meals (dynamic, driven by [meals] list).
/// Columns = Mon–Sun.
/// Cells show if a meal is enabled on that day and allow toggling.
class MealScheduleGrid extends StatefulWidget {
  const MealScheduleGrid({
    super.key,
    required this.meals,
    required this.schedule,
    this.onCellToggle,
    this.readOnly = false,
  });

  final List<MealModel> meals;
  final MealScheduleModel? schedule;
  final void Function(String mealId, int weekdayIndex, bool enabled)?
      onCellToggle;
  final bool readOnly;

  @override
  State<MealScheduleGrid> createState() => _MealScheduleGridState();
}

class _MealScheduleGridState extends State<MealScheduleGrid> {
  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Local toggle state: mealId -> List<bool>(7)
  late Map<String, List<bool>> _enabled;

  @override
  void initState() {
    super.initState();
    _buildEnabledMap();
  }

  @override
  void didUpdateWidget(MealScheduleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schedule != widget.schedule ||
        oldWidget.meals != widget.meals) {
      _buildEnabledMap();
    }
  }

  void _buildEnabledMap() {
    _enabled = {};
    for (final meal in widget.meals) {
      _enabled[meal.id] = List.filled(7, true); // default: all days enabled
    }

    // Apply schedule overrides if available.
    // DayOfWeek index (0 = Mon … 6 = Sun) maps to the 7-day array.
    final schedule = widget.schedule;
    if (schedule != null) {
      for (final daySchedule in schedule.days) {
        final dayIdx = daySchedule.day.index; // 0 = monday … 6 = sunday
        for (final mealEntry in daySchedule.meals) {
          if (_enabled.containsKey(mealEntry.mealId)) {
            _enabled[mealEntry.mealId]![dayIdx] = true;
          }
        }
        // Mark meals NOT in this day's schedule as disabled
        for (final meal in widget.meals) {
          if (!daySchedule.meals.any((e) => e.mealId == meal.id)) {
            _enabled[meal.id]![dayIdx] = false;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.meals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No meals configured yet.\nAdd meals in Meal Config.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ───────────────────────────────────────────────
            Row(
              children: [
                const SizedBox(width: 100), // meal label column
                ..._dayLabels.map(
                  (d) => _Cell(
                    backgroundColor:
                        colorScheme.surfaceContainerHighest,
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            // ── Meal rows ────────────────────────────────────────────────
            ...widget.meals.map((meal) {
              final row = _enabled[meal.id] ?? List.filled(7, true);
              return Row(
                children: [
                  // Meal label
                  SizedBox(
                    width: 100,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meal.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            meal.slotKey,
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Day cells
                  ...List.generate(7, (dayIdx) {
                    final isEnabled = row[dayIdx];
                    return _ToggleCell(
                      isEnabled: isEnabled,
                      readOnly: widget.readOnly,
                      onToggle: widget.readOnly
                          ? null
                          : () {
                              setState(() {
                                row[dayIdx] = !isEnabled;
                              });
                              widget.onCellToggle?.call(
                                meal.id,
                                dayIdx,
                                !isEnabled,
                              );
                            },
                    );
                  }),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Grid cell ─────────────────────────────────────────────────────────────────

class _Cell extends StatelessWidget {
  const _Cell({required this.child, this.backgroundColor});
  final Widget child;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 40,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _ToggleCell extends StatelessWidget {
  const _ToggleCell({
    required this.isEnabled,
    required this.readOnly,
    this.onToggle,
  });

  final bool isEnabled;
  final bool readOnly;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 40,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isEnabled
              ? AppColors.present.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isEnabled
                ? AppColors.present.withValues(alpha: 0.3)
                : Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.3),
    
          ),
        ),
      ),
    );
  }
}

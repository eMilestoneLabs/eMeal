import 'package:flutter/material.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';

/// Horizontal scrolling day-selector strip for the weekly menu.
///
/// Shows Mon–Sun chips.  The selected day is highlighted with an indigo pill.
/// Days with meals show a small dot indicator beneath the label.
class WeeklyMenuGrid extends StatelessWidget {
  const WeeklyMenuGrid({
    super.key,
    required this.selectedDay,
    required this.daysWithMeals,
    required this.onDaySelected,
  });

  final DayOfWeek selectedDay;

  /// Set of days that have at least one meal configured — show indicator dot.
  final Set<DayOfWeek> daysWithMeals;

  final ValueChanged<DayOfWeek> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final today = DayOfWeek.fromWeekday(DateTime.now().weekday);

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: DayOfWeek.values.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final day = DayOfWeek.values[index];
          final isSelected = day == selectedDay;
          final isToday = day == today;
          final hasMeals = daysWithMeals.contains(day);

          return GestureDetector(
            onTap: () => onDaySelected(day),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              width: 52,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: isToday && !isSelected
                    ? Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      )
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day.shortLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasMeals
                          ? (isSelected
                              ? colorScheme.onPrimary.withValues(alpha: 0.8)
                              : colorScheme.primary)
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

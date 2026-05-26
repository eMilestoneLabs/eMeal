import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';

/// Static mock meal data for MVP development.
///
/// The weekly schedule demonstrates fully INDEPENDENT per-day configurations:
/// - Each day carries its own [DayMealEntry] objects.
/// - Wednesday has no Dinner scheduled.
/// - Saturday has no Breakfast.
/// - Sunday has a special brunch slot and no Dinner.
/// - Every day's menu items are unique — editing one day does NOT propagate.
abstract final class MockMealsData {
  static List<MealModel> groupMeals({
    String groupId = 'grp_001',
    String organizationId = 'org_001',
  }) =>
      [
        MealModel(
          id: 'meal_001',
          groupId: groupId,
          organizationId: organizationId,
          name: 'Breakfast',
          slotKey: 'breakfast',
          order: 0,
          attendanceWindow: const MealAttendanceWindow(
            openTime: '07:00',
            closeTime: '09:00',
          ),
          isActive: true,
          menuItems: const [
            'Idli Sambar',
            'Medu Vada',
            'Bread & Butter',
            'Tea / Coffee',
          ],
        ),
        MealModel(
          id: 'meal_002',
          groupId: groupId,
          organizationId: organizationId,
          name: 'Lunch',
          slotKey: 'lunch',
          order: 1,
          attendanceWindow: const MealAttendanceWindow(
            openTime: '12:00',
            closeTime: '14:00',
          ),
          isActive: true,
          menuItems: const [
            'Rice',
            'Dal',
            'Sabzi',
            'Roti',
            'Salad',
            'Pickle',
          ],
        ),
        MealModel(
          id: 'meal_003',
          groupId: groupId,
          organizationId: organizationId,
          name: 'Dinner',
          slotKey: 'dinner',
          order: 2,
          attendanceWindow: const MealAttendanceWindow(
            openTime: '19:00',
            closeTime: '21:00',
          ),
          isActive: true,
          menuItems: const [
            'Roti',
            'Paneer / Chicken Curry',
            'Rice',
            'Dal',
            'Dessert',
          ],
        ),
      ];

  /// Returns a weekly schedule with INDEPENDENT per-day meal configurations.
  ///
  /// This demonstrates the core architecture guarantee: each [DayMealEntry]
  /// is a distinct object.  Mutating Monday's entry in [MealConfigProvider]
  /// leaves every other day unchanged.
  static MealScheduleModel weekSchedule({
    String groupId = 'grp_001',
    String organizationId = 'org_001',
  }) {
    return MealScheduleModel(
      id: 'sched_001',
      groupId: groupId,
      organizationId: organizationId,
      isPublished: true,
      days: [
        // ── Monday ──────────────────────────────────────────────────────────
        const DaySchedule(day: DayOfWeek.monday, meals: [
          DayMealEntry(
            mealId: 'meal_001', name: 'Breakfast', slotKey: 'breakfast',
            order: 0,
            menuItems: ['Idli Sambar', 'Medu Vada', 'Tea / Coffee'],
          ),
          DayMealEntry(
            mealId: 'meal_002', name: 'Lunch', slotKey: 'lunch',
            order: 1,
            menuItems: ['Dal Rice', 'Aloo Sabzi', 'Roti', 'Salad', 'Pickle'],
          ),
          DayMealEntry(
            mealId: 'meal_003', name: 'Dinner', slotKey: 'dinner',
            order: 2,
            menuItems: ['Paneer Butter Masala', 'Roti', 'Rice', 'Kheer'],
          ),
        ]),

        // ── Tuesday ──────────────────────────────────────────────────────────
        const DaySchedule(day: DayOfWeek.tuesday, meals: [
          DayMealEntry(
            mealId: 'meal_001', name: 'Breakfast', slotKey: 'breakfast',
            order: 0,
            menuItems: ['Poha', 'Bread Toast', 'Boiled Eggs', 'Juice'],
          ),
          DayMealEntry(
            mealId: 'meal_002', name: 'Lunch', slotKey: 'lunch',
            order: 1,
            menuItems: ['Rajma Rice', 'Mixed Sabzi', 'Roti', 'Raita'],
          ),
          DayMealEntry(
            mealId: 'meal_003', name: 'Dinner', slotKey: 'dinner',
            order: 2,
            menuItems: ['Chicken Curry', 'Rice', 'Roti', 'Salad'],
          ),
        ]),

        // ── Wednesday — no Dinner scheduled ─────────────────────────────────
        const DaySchedule(day: DayOfWeek.wednesday, meals: [
          DayMealEntry(
            mealId: 'meal_001', name: 'Breakfast', slotKey: 'breakfast',
            order: 0,
            menuItems: ['Upma', 'Coconut Chutney', 'Tea / Coffee'],
          ),
          DayMealEntry(
            mealId: 'meal_002', name: 'Lunch', slotKey: 'lunch',
            order: 1,
            menuItems: ['Dal Tadka', 'Jeera Rice', 'Roti', 'Papad', 'Pickle'],
          ),
          // No dinner entry — Wednesday Dinner is disabled.
        ]),

        // ── Thursday ─────────────────────────────────────────────────────────
        const DaySchedule(day: DayOfWeek.thursday, meals: [
          DayMealEntry(
            mealId: 'meal_001', name: 'Breakfast', slotKey: 'breakfast',
            order: 0,
            menuItems: ['Puri Bhaji', 'Halwa', 'Tea / Coffee'],
          ),
          DayMealEntry(
            mealId: 'meal_002', name: 'Lunch', slotKey: 'lunch',
            order: 1,
            menuItems: ['Chole Rice', 'Roti', 'Raita', 'Salad'],
          ),
          DayMealEntry(
            mealId: 'meal_003', name: 'Dinner', slotKey: 'dinner',
            order: 2,
            menuItems: ['Fish Curry', 'Rice', 'Roti', 'Dal', 'Dessert'],
          ),
        ]),

        // ── Friday ───────────────────────────────────────────────────────────
        const DaySchedule(day: DayOfWeek.friday, meals: [
          DayMealEntry(
            mealId: 'meal_001', name: 'Breakfast', slotKey: 'breakfast',
            order: 0,
            menuItems: ['Dosa', 'Sambar', 'Coconut Chutney', 'Coffee'],
          ),
          DayMealEntry(
            mealId: 'meal_002', name: 'Lunch', slotKey: 'lunch',
            order: 1,
            menuItems: ['Biryani', 'Raita', 'Salad', 'Pickle'],
          ),
          DayMealEntry(
            mealId: 'meal_003', name: 'Dinner', slotKey: 'dinner',
            order: 2,
            menuItems: ['Mutton Curry', 'Roti', 'Rice', 'Dal', 'Ice Cream'],
          ),
        ]),

        // ── Saturday — no Breakfast scheduled ───────────────────────────────
        const DaySchedule(day: DayOfWeek.saturday, meals: [
          // No breakfast — Saturday breakfast is disabled.
          DayMealEntry(
            mealId: 'meal_002', name: 'Lunch', slotKey: 'lunch',
            order: 1,
            menuItems: ['Veg Thali', 'Roti', 'Rice', 'Dal', 'Salad'],
          ),
          DayMealEntry(
            mealId: 'meal_003', name: 'Dinner', slotKey: 'dinner',
            order: 2,
            menuItems: ['Egg Curry', 'Roti', 'Rice', 'Halwa'],
          ),
        ]),

        // ── Sunday — special brunch, no Dinner ──────────────────────────────
        const DaySchedule(day: DayOfWeek.sunday, meals: [
          DayMealEntry(
            mealId: 'meal_001', name: 'Brunch', slotKey: 'breakfast',
            order: 0,
            openTime: '09:00',
            closeTime: '11:00',
            menuItems: [
              'Chole Bhature',
              'Halwa Puri',
              'Fruit Salad',
              'Lassi',
              'Tea / Coffee',
            ],
          ),
          DayMealEntry(
            mealId: 'meal_002', name: 'Lunch', slotKey: 'lunch',
            order: 1,
            menuItems: ['Dal Makhani', 'Naan', 'Jeera Rice', 'Raita', 'Gulab Jamun'],
          ),
          // No dinner on Sunday.
        ]),
      ],
    );
  }
}

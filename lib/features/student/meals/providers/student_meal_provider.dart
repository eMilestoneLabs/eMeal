import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

/// Drives the student "Weekly Menu" and "Meal Detail" screens.
///
/// Lifecycle: created once per student shell session; dispose when the shell
/// is torn down.  Call [load] with the current user's group / org ids.
class StudentMealProvider extends ChangeNotifier {
  StudentMealProvider({MealRepository? repository})
      : _repo = repository ?? MealRepository();

  final MealRepository _repo;

  // ── State ──────────────────────────────────────────────────────────────────

  MealScheduleModel? _schedule;
  DayOfWeek _selectedDay = DayOfWeek.fromWeekday(DateTime.now().weekday);
  bool _isLoading = false;
  String? _error;

  // IDs populated on [load]
  String _organizationId = '';
  String _groupId = '';

  // ── Public getters ─────────────────────────────────────────────────────────

  MealScheduleModel? get schedule => _schedule;
  DayOfWeek get selectedDay => _selectedDay;
  bool get isLoading => _isLoading;
  String? get error => _error;
  // Issue 3: a placeholder schedule (id '') is "nothing published", not a real
  // schedule — so the menu shows the empty state until the admin publishes.
  bool get hasSchedule => _schedule != null && _schedule!.id.isNotEmpty;

  /// The [DaySchedule] for the currently selected day, or null.
  DaySchedule? get mealsForSelectedDay => _schedule?.scheduleFor(_selectedDay);

  /// The set of DayOfWeek values that have at least one meal configured.
  Set<DayOfWeek> get daysWithMeals {
    final s = _schedule;
    if (s == null) return {};
    return {
      for (final ds in s.days)
        if (ds.meals.isNotEmpty) ds.day,
    };
  }

  // ── Load ───────────────────────────────────────────────────────────────────

  /// Fetch the current week schedule for [groupId] in [organizationId].
  Future<void> load({
    required String organizationId,
    required String groupId,
    bool forceRefresh = false,
  }) async {
    if (_isLoading) return;
    // Issue 3: an empty placeholder schedule (id '') means "nothing published
    // yet" — never cache it, so the menu refreshes once the admin publishes.
    if (!forceRefresh && _schedule != null && _schedule!.id.isNotEmpty) return;

    _organizationId = organizationId;
    _groupId = groupId;

    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _repo.getCurrentWeekSchedule(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok(:final value):
        _schedule = value;
        _error = null;
        _ensureValidDay();
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Refresh the schedule (always re-fetches from the repo).
  Future<void> refresh() => load(
        organizationId: _organizationId,
        groupId: _groupId,
        forceRefresh: true,
      );

  // ── Day selection ──────────────────────────────────────────────────────────

  /// Select [day] and notify listeners.
  void selectDay(DayOfWeek day) {
    if (_selectedDay == day) return;
    _selectedDay = day;
    notifyListeners();
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  void _ensureValidDay() {
    final today = DayOfWeek.fromWeekday(DateTime.now().weekday);
    final current = _schedule?.scheduleFor(_selectedDay);
    if (current == null || current.isEmpty) {
      final todaySchedule = _schedule?.scheduleFor(today);
      if (todaySchedule != null && todaySchedule.isNotEmpty) {
        _selectedDay = today;
      }
    }
  }
}

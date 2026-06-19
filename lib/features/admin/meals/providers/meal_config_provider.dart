import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default preference tags used when enabling preferences globally.
/// Mirrors the same constant in [MealConfigForm] to keep them in sync.
const _kGlobalDefaultPreferenceTags = [
  'Veg',
  'Non-Veg',
  'Egg',
  'Fish',
  'Chicken',
  'Jain',
];

/// State manager for admin meal configuration.
///
/// Repository-driven architecture using [MealRepository] and [GroupRepository].
/// Supports fully dynamic meal creation — any number, any names, any order.
class MealConfigProvider extends ChangeNotifier {
  MealConfigProvider({
    MealRepository? mealRepo,
    GroupRepository? groupRepo,
  })  : _mealRepo = mealRepo ?? MealRepository(),
        _groupRepo = groupRepo ?? GroupRepository();

  final MealRepository _mealRepo;
  final GroupRepository _groupRepo;

  // ── State ─────────────────────────────────────────────────────────────────

  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  List<MealModel> _meals = [];
  List<GroupModel> _groups = [];
  GroupModel? _selectedGroup;
  MealScheduleModel? _weekSchedule;

  bool _mealsEnabled = true;
  bool _preferencesEnabled = false;
  // Enhancement 3: per-group 'Continue Recurring Weekly Menu' toggle.
  bool _autoContinueLastWeek = false;

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  List<MealModel> get meals => _meals;
  List<GroupModel> get groups => _groups;
  GroupModel? get selectedGroup => _selectedGroup;
  MealScheduleModel? get weekSchedule => _weekSchedule;
  bool get mealsEnabled => _mealsEnabled;
  bool get preferencesEnabled => _preferencesEnabled;
  bool get autoContinueLastWeek => _autoContinueLastWeek;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> loadGroups({required String organizationId}) async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _groupRepo.getOrganisationGroups(
      organizationId: organizationId,
    );

    switch (result) {
      case Ok(:final value):
        _groups = value.data;
        if (_selectedGroup == null && _groups.isNotEmpty) {
          await _loadForGroup(_groups.first, organizationId: organizationId);
        }
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> selectGroup(
    GroupModel group, {
    required String organizationId,
  }) async {
    _selectedGroup = group;
    _mealsEnabled = group.mealConfig.mealsEnabled;
    _preferencesEnabled = group.mealConfig.preferencesEnabled;
    notifyListeners();
    await _loadMeals(
      organizationId: organizationId,
      groupId: group.id,
    );
    await _loadRecurringFlag(group.id);
  }

  Future<void> _loadForGroup(
    GroupModel group, {
    required String organizationId,
  }) async {
    _selectedGroup = group;
    _mealsEnabled = group.mealConfig.mealsEnabled;
    _preferencesEnabled = group.mealConfig.preferencesEnabled;
    await _loadMeals(
      organizationId: organizationId,
      groupId: group.id,
    );
    await _loadRecurringFlag(group.id);
  }

  Future<void> _loadMeals({
    required String organizationId,
    required String groupId,
  }) async {
    final result = await _mealRepo.getGroupMeals(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok(:final value):
        // Sort by admin-set order for consistent display
        _meals = List.of(value)
          ..sort((a, b) => a.order.compareTo(b.order));
      case Err(:final failure):
        _error = failure.message;
    }
    notifyListeners();
  }

  Future<void> loadSchedule({
    required String organizationId,
    required String groupId,
  }) async {
    // Issue 4: keep the loading state on until the draft is populated, so the
    // planner shows a spinner instead of flashing "No schedule yet" before the
    // master meals auto-fill the week.
    _isLoading = true;
    notifyListeners();
    final result = await _mealRepo.getCurrentWeekSchedule(
      organizationId: organizationId,
      groupId: groupId,
    );

    switch (result) {
      case Ok(:final value):
        _weekSchedule = value;
      case Err(:final failure):
        _error = failure.message;
    }
    // Issue 1 (#2): a freshly-loaded DRAFT must already contain every enabled
    // meal on all 7 weekdays so the admin can immediately configure each day,
    // and so per-day toggles always apply. Never touches a published plan or a
    // draft the admin has already started configuring.
    await _ensureWeekdaysPopulated(groupId);
    _isLoading = false;
    notifyListeners();
  }

  /// Additive (Issue 1 #2): auto-populate an EMPTY draft with all active meals
  /// on every weekday. No-op when published, when there are no active meals, or
  /// when the draft already has at least one configured day.
  Future<void> _ensureWeekdaysPopulated(String groupId) async {
    final sched = _weekSchedule;
    if (sched == null) return;
    if (sched.isPublished) return;
    if (!_meals.any((m) => m.isActive)) return;
    final allEmpty =
        sched.days.isEmpty || sched.days.every((d) => d.meals.isEmpty);
    if (!allEmpty) return;
    // Enhancement 3: when recurring is ON and we cached the last published
    // week's per-day config, carry it forward; otherwise default-populate (#2).
    if (_autoContinueLastWeek && await _restoreRecurringTemplate(groupId)) {
      return;
    }
    // copyFromPreviousWeek builds all 7 days with every active meal enabled.
    copyFromPreviousWeek();
  }

  // ── Enhancement 3: Continue Recurring Weekly Menu (frontend MVP) ───────────

  static String _recurringFlagKey(String groupId) => 'meal_recurring_$groupId';
  static String _recurringTemplateKey(String groupId) =>
      'meal_recurring_template_$groupId';

  Future<void> _loadRecurringFlag(String groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoContinueLastWeek = prefs.getBool(_recurringFlagKey(groupId)) ?? false;
    } catch (_) {
      _autoContinueLastWeek = false;
    }
    notifyListeners();
  }

  /// Enables/disables 'Continue Recurring Weekly Menu' for [groupId] and
  /// persists it. When turned ON it immediately carries the most-recent
  /// per-day config into the current EMPTY draft.
  Future<void> setAutoContinueLastWeek(
    bool value, {
    required String groupId,
  }) async {
    _autoContinueLastWeek = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_recurringFlagKey(groupId), value);
    } catch (_) {}
    final sched = _weekSchedule;
    final emptyDraft = sched != null &&
        !sched.isPublished &&
        _meals.any((m) => m.isActive) &&
        (sched.days.isEmpty || sched.days.every((d) => d.meals.isEmpty));
    if (value && emptyDraft) {
      if (!await _restoreRecurringTemplate(groupId)) {
        copyFromPreviousWeek();
      }
    }
  }

  /// Caches a published schedule so recurring can carry it forward later.
  Future<void> _saveRecurringTemplate(
    String groupId,
    MealScheduleModel schedule,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _recurringTemplateKey(groupId),
        jsonEncode(schedule.toJson()),
      );
    } catch (_) {}
  }

  /// Restores the cached recurring template into the current (empty) draft.
  /// Returns true when a non-empty template was applied.
  Future<bool> _restoreRecurringTemplate(String groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_recurringTemplateKey(groupId));
      if (raw == null || raw.isEmpty) return false;
      final tmpl = MealScheduleModel.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (tmpl.days.isEmpty || tmpl.days.every((d) => d.meals.isEmpty)) {
        return false;
      }
      final cur = _weekSchedule;
      if (cur == null) return false;
      // Carry per-day config forward as a NEW DRAFT for the current week.
      _weekSchedule = MealScheduleModel(
        id: cur.id,
        groupId: cur.groupId,
        organizationId: cur.organizationId,
        days: tmpl.days,
        isPublished: false,
        publishedAt: cur.publishedAt,
        createdAt: cur.createdAt,
      );
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Meal CRUD ─────────────────────────────────────────────────────────────

  Future<MealModel?> createMeal({
    required String organizationId,
    required String groupId,
    required String name,
    required String slotKey,
    required int order,
    required MealAttendanceWindow attendanceWindow,
    String? description,
    List<String> menuItems = const [],
    List<String> availablePreferences = const [],
    List<Uint8List> imageBytes = const [],
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    // Defense-in-depth: compress + validate even if the form already did so.
    final safeImages = await _compressImages(imageBytes);
    if (safeImages == null) {
      // _error + notifyListeners already called inside _compressImages.
      _isSaving = false;
      notifyListeners();
      return null;
    }

    final result = await _mealRepo.createMeal(
      organizationId: organizationId,
      groupId: groupId,
      name: name,
      slotKey: slotKey,
      order: order,
      attendanceWindow: attendanceWindow,
      description: description,
      menuItems: menuItems,
      availablePreferences: availablePreferences,
      imageBytes: safeImages,
    );

    switch (result) {
      case Ok(:final value):
        _meals = [..._meals, value]
          ..sort((a, b) => a.order.compareTo(b.order));
        _isSaving = false;
        notifyListeners();
        return value;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return null;
    }
  }

  Future<bool> updateMeal({
    required String organizationId,
    required String groupId,
    required String mealId,
    String? name,
    String? description,
    List<String>? menuItems,
    List<String>? availablePreferences,
    MealAttendanceWindow? attendanceWindow,
    bool? isActive,
    List<Uint8List>? imageBytes,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    // Compress + validate images if provided.
    List<Uint8List>? safeImages;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      safeImages = await _compressImages(imageBytes);
      if (safeImages == null) {
        _isSaving = false;
        notifyListeners();
        return false;
      }
    }

    final result = await _mealRepo.updateMeal(
      organizationId: organizationId,
      groupId: groupId,
      mealId: mealId,
      name: name,
      description: description,
      menuItems: menuItems,
      availablePreferences: availablePreferences,
      attendanceWindow: attendanceWindow,
      isActive: isActive,
      imageBytes: safeImages ?? imageBytes,
    );

    switch (result) {
      case Ok(:final value):
        final idx = _meals.indexWhere((m) => m.id == mealId);
        if (idx != -1) {
          _meals = List.of(_meals)..[idx] = value;
        }
        _isSaving = false;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return false;
    }
  }

  Future<bool> deleteMeal({
    required String organizationId,
    required String groupId,
    required String mealId,
  }) async {
    final result = await _mealRepo.deleteMeal(
      organizationId: organizationId,
      groupId: groupId,
      mealId: mealId,
    );

    switch (result) {
      case Ok():
        _meals = _meals.where((m) => m.id != mealId).toList();
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── Toggles ───────────────────────────────────────────────────────────────

  Future<bool> toggleMealSystem({
    required String organizationId,
    required String groupId,
    required bool enabled,
  }) async {
    if (_selectedGroup == null) return false;
    _isSaving = true;
    notifyListeners();

    final updatedConfig = _selectedGroup!.mealConfig.copyWith(
      mealsEnabled: enabled,
    );

    final result = await _groupRepo.updateGroup(
      organizationId: organizationId,
      groupId: groupId,
      mealConfig: updatedConfig,
    );

    switch (result) {
      case Ok(:final value):
        _selectedGroup = value;
        _mealsEnabled = enabled;
        _isSaving = false;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return false;
    }
  }

  Future<bool> togglePreferences({
    required String organizationId,
    required String groupId,
    required bool enabled,
    List<MealPreferenceOption>? enabledPreferences,
  }) async {
    if (_selectedGroup == null) return false;
    _isSaving = true;
    notifyListeners();

    final updatedConfig = _selectedGroup!.mealConfig.copyWith(
      preferencesEnabled: enabled,
      enabledPreferences: enabledPreferences ??
          _selectedGroup!.mealConfig.enabledPreferences,
    );

    final result = await _groupRepo.updateGroup(
      organizationId: organizationId,
      groupId: groupId,
      mealConfig: updatedConfig,
    );

    switch (result) {
      case Ok(:final value):
        _selectedGroup = value;
        _preferencesEnabled = enabled;
        // When enabling the global preference toggle, inherit to all meals
        // that don't already have preferences on.  This makes the global
        // toggle behave as a master controller — admins can still override
        // individual meals off in the meal edit form.
        if (enabled) {
          _meals = _meals.map((m) {
            if (m.preferencesEnabled) return m; // already on — preserve
            return m.copyWith(
              preferencesEnabled: true,
              enabledPreferences: m.enabledPreferences.isNotEmpty
                  ? m.enabledPreferences
                  : List<String>.from(_kGlobalDefaultPreferenceTags),
            );
          }).toList();
        }
        _isSaving = false;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return false;
    }
  }

  // ── Schedule ──────────────────────────────────────────────────────────────

  /// Persists the current draft to the backend (create if new, else update),
  /// keeping [_weekSchedule] in sync with the real server id. Returns the
  /// persisted schedule id, or null on failure. Issue #12.
  Future<String?> saveDraft({
    required String organizationId,
    required String groupId,
  }) async {
    if (_weekSchedule == null) return null;
    _isSaving = true;
    notifyListeners();

    final result = await _mealRepo.saveSchedule(
      organizationId: organizationId,
      groupId: groupId,
      schedule: _weekSchedule!,
    );
    switch (result) {
      case Ok(:final value):
        _weekSchedule = value;
        _isSaving = false;
        notifyListeners();
        return value.id;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return null;
    }
  }

  Future<bool> publishSchedule({
    required String organizationId,
    required String groupId,
  }) async {
    if (_weekSchedule == null) return false;
    _isSaving = true;
    notifyListeners();

    // Issue #12: a locally-built draft has an empty id. Persist it first (create
    // or update) so publish targets a real /schedules/:id — never the broken
    // /schedules//publish that produced "Cannot POST /api/v1/schedules/publish".
    final saveResult = await _mealRepo.saveSchedule(
      organizationId: organizationId,
      groupId: groupId,
      schedule: _weekSchedule!,
    );
    final String scheduleId;
    switch (saveResult) {
      case Ok(:final value):
        _weekSchedule = value;
        scheduleId = value.id;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return false;
    }
    if (scheduleId.isEmpty) {
      _error = 'Could not create schedule. Add meals first, then publish.';
      _isSaving = false;
      notifyListeners();
      return false;
    }

    final result = await _mealRepo.publishSchedule(
      organizationId: organizationId,
      groupId: groupId,
      scheduleId: scheduleId,
    );

    switch (result) {
      case Ok(:final value):
        _weekSchedule = value;
        // Enhancement 3: remember this published week so recurring can carry
        // its per-day config forward into the next empty week.
        if (_autoContinueLastWeek) {
          await _saveRecurringTemplate(groupId, value);
        }
        _isSaving = false;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return false;
    }
  }

  /// Issue 2: revert a PUBLISHED schedule back to draft so the admin can edit
  /// and re-publish. No-op when there is no persisted schedule (empty id).
  Future<bool> revertToDraft({
    required String organizationId,
    required String groupId,
  }) async {
    final scheduleId = _weekSchedule?.id ?? '';
    if (scheduleId.isEmpty) return false;
    _isSaving = true;
    notifyListeners();

    final result = await _mealRepo.revertSchedule(
      organizationId: organizationId,
      groupId: groupId,
      scheduleId: scheduleId,
    );
    switch (result) {
      case Ok(:final value):
        _weekSchedule = value;
        _isSaving = false;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        _isSaving = false;
        notifyListeners();
        return false;
    }
  }

  // ── Legacy compat ──────────────────────────────────────────────────────────

  Future<bool> saveMealWindow({
    required String mealId,
    required String openTime,
    required String closeTime,
  }) async {
    final meal = _meals.firstWhere(
      (m) => m.id == mealId,
      orElse: () => _meals.first,
    );
    return updateMeal(
      organizationId: meal.organizationId,
      groupId: meal.groupId,
      mealId: mealId,
      attendanceWindow: MealAttendanceWindow(
        openTime: openTime,
        closeTime: closeTime,
      ),
    );
  }

  /// Copies the current week's schedule to represent "previous week" as a
  /// convenience — effectively resets all days to have all active meals enabled.
  /// On the backend this would fetch the previous ISO-week's published schedule.
  void copyFromPreviousWeek() {
    if (_weekSchedule == null || _meals.isEmpty) return;

    final allDays = DayOfWeek.values.map((day) {
      final entries = _meals
          .where((m) => m.isActive)
          .map((m) => DayMealEntry(
                mealId: m.id,
                name: m.name,
                slotKey: m.slotKey,
                order: m.order,
                menuItems: m.menuItems,
                preferencesEnabled: m.preferencesEnabled,
                enabledPreferences: m.enabledPreferences,
              ))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      return DaySchedule(day: day, meals: entries);
    }).toList();

    _weekSchedule = MealScheduleModel(
      id: _weekSchedule!.id,
      groupId: _weekSchedule!.groupId,
      organizationId: _weekSchedule!.organizationId,
      days: allDays,
      isPublished: false,
      publishedAt: _weekSchedule!.publishedAt,
      createdAt: _weekSchedule!.createdAt,
    );
    notifyListeners();
  }

  /// Updates a single [DayMealEntry] for [day] and [mealId].
  ///
  /// Only supplied fields change; all other fields remain untouched.
  /// This is the mechanism for **per-day independent** meal configuration —
  /// editing Monday's Breakfast never affects any other day's entry.
  ///
  /// Automatically marks the schedule as draft so the admin must re-publish.
  void updateDayMealEntry(
    DayOfWeek day,
    String mealId, {
    String? name,
    List<String>? menuItems,
    String? openTime,
    String? closeTime,
    bool? preferencesEnabled,
    List<String>? enabledPreferences,
  }) {
    if (_weekSchedule == null) return;

    final updatedDays = _weekSchedule!.days.map((daySchedule) {
      if (daySchedule.day != day) return daySchedule;

      final updatedMeals = daySchedule.meals.map((entry) {
        if (entry.mealId != mealId) return entry;
        return DayMealEntry(
          mealId: entry.mealId,
          name: name ?? entry.name,
          slotKey: entry.slotKey,
          order: entry.order,
          menuItems: menuItems ?? entry.menuItems,
          imageUrl: entry.imageUrl,
          openTime: openTime ?? entry.openTime,
          closeTime: closeTime ?? entry.closeTime,
          preferencesEnabled: preferencesEnabled ?? entry.preferencesEnabled,
          enabledPreferences: enabledPreferences ?? entry.enabledPreferences,
        );
      }).toList();

      return DaySchedule(day: daySchedule.day, meals: updatedMeals);
    }).toList();

    _weekSchedule = MealScheduleModel(
      id: _weekSchedule!.id,
      groupId: _weekSchedule!.groupId,
      organizationId: _weekSchedule!.organizationId,
      days: updatedDays,
      isPublished: false,   // editing always reverts to draft
      publishedAt: _weekSchedule!.publishedAt,
      createdAt: _weekSchedule!.createdAt,
    );
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // ── Image compression guard ────────────────────────────────────────────────

  /// Compresses each image in [raw] to JPEG quality 70 / maxWidth 1080, then
  /// enforces the 200 KB combined cap defined by [AppConstants.maxMealImageBytes].
  ///
  /// Returns the compressed list on success, or sets [_error] and returns null
  /// if the images exceed the cap even after compression.
  ///
  /// Called by [createMeal] and [updateMeal] as a defense-in-depth safeguard:
  /// the form UI already compresses before passing bytes here, but the provider
  /// must not rely solely on the view layer for a business constraint.
  ///
  /// PHASE_B6: When the real backend is wired, the server will enforce its own
  /// size limit; this client-side guard remains valuable for immediate feedback.
  Future<List<Uint8List>?> _compressImages(List<Uint8List> raw) async {
    if (raw.isEmpty) return raw;

    const int cap = AppConstants.maxMealImageBytes;
    final compressed = <Uint8List>[];

    for (final bytes in raw) {
      // Skip re-compression if already small enough (e.g. already processed
      // by the form's _pickImages). Threshold: single-image share of the cap.
      if (bytes.length <= cap ~/ raw.length) {
        compressed.add(bytes);
        continue;
      }

      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 70,
        minWidth: 1080,
        minHeight: 720,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (result.isNotEmpty) compressed.add(result);
    }

    final total = compressed.fold<int>(0, (s, b) => s + b.length);
    if (total > cap) {
      _error = 'Images exceed the ${cap ~/ 1024} KB combined limit even after '
          'compression. Please use smaller photos.';
      notifyListeners();
      return null;
    }

    return compressed;
  }

  /// Alias getter for screens that reference weeklySchedule.
  MealScheduleModel? get weeklySchedule => _weekSchedule;

  /// Toggles a meal on/off for a specific weekday in the local schedule state.
  void toggleMealDay(String mealId, int weekdayIndex, bool enabled) {
    if (_weekSchedule == null) return;

    final targetDay = DayOfWeek.values[weekdayIndex % 7];
    final updatedDays = _weekSchedule!.days.map((daySchedule) {
      if (daySchedule.day != targetDay) return daySchedule;

      final List<DayMealEntry> entries = List<DayMealEntry>.from(daySchedule.meals);
      if (enabled) {
        final alreadyPresent = entries.any((e) => e.mealId == mealId);
        if (!alreadyPresent) {
          final meal = _meals.firstWhere(
            (m) => m.id == mealId,
            orElse: () => _meals.first,
          );
          entries.add(DayMealEntry(
            mealId: meal.id,
            name: meal.name,
            slotKey: meal.slotKey,
            order: meal.order,
            // Copy menu items from the template so the newly-enabled day
            // entry starts with the same content as the shared meal.
            menuItems: List<String>.from(meal.menuItems),
            preferencesEnabled: meal.preferencesEnabled,
            enabledPreferences: meal.enabledPreferences,
          ));
          entries.sort((a, b) => a.order.compareTo(b.order));
        }
      } else {
        entries.removeWhere((e) => e.mealId == mealId);
      }
      return DaySchedule(day: daySchedule.day, meals: entries);
    }).toList();

    _weekSchedule = MealScheduleModel(
      id: _weekSchedule!.id,
      groupId: _weekSchedule!.groupId,
      organizationId: _weekSchedule!.organizationId,
      days: updatedDays,
      isPublished: _weekSchedule!.isPublished,
      publishedAt: _weekSchedule!.publishedAt,
      createdAt: _weekSchedule!.createdAt,
    );
    notifyListeners();
  }

  /// Copies all meal entries from [fromDay] to [toDay], replacing [toDay]'s
  /// current schedule with an independent deep copy.
  ///
  /// After copying, the two days are fully independent: editing [toDay]'s
  /// meals will never affect [fromDay]'s meals.
  void copyDaySchedule(DayOfWeek fromDay, DayOfWeek toDay) {
    if (_weekSchedule == null) return;

    final source = _weekSchedule!.forDay(fromDay);
    if (source == null || source.isEmpty) return;

    // Deep-copy entries so the two days share no object references.
    // openTime/closeTime overrides are also copied independently.
    final copiedEntries = source.meals
        .map((e) => DayMealEntry(
              mealId: e.mealId,
              name: e.name,
              slotKey: e.slotKey,
              order: e.order,
              menuItems: List<String>.from(e.menuItems),
              imageUrl: e.imageUrl,
              openTime: e.openTime,
              closeTime: e.closeTime,
              preferencesEnabled: e.preferencesEnabled,
              enabledPreferences: e.enabledPreferences,
            ))
        .toList();

    final updatedDays = _weekSchedule!.days.map((daySchedule) {
      if (daySchedule.day != toDay) return daySchedule;
      return DaySchedule(day: toDay, meals: copiedEntries);
    }).toList();

    _weekSchedule = MealScheduleModel(
      id: _weekSchedule!.id,
      groupId: _weekSchedule!.groupId,
      organizationId: _weekSchedule!.organizationId,
      days: updatedDays,
      isPublished: false,
      publishedAt: _weekSchedule!.publishedAt,
      createdAt: _weekSchedule!.createdAt,
    );
    notifyListeners();
  }
}

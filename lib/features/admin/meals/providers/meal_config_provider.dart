import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/core/utils/image_compression.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/data/repositories/group_repository.dart';
import 'package:smart_meal_management/data/repositories/meal_repository.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';
import 'package:smart_meal_management/shared/models/meal_schedule_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';
import 'package:smart_meal_management/data/services/image_cache_seeder.dart';
import 'package:smart_meal_management/data/services/response_cache_service.dart';
import 'package:smart_meal_management/data/services/selected_group_store.dart';
import 'package:smart_meal_management/data/services/selected_group_subscription.dart';

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
  // Additive: per-group meal pricing toggle.
  bool _mealPricingEnabled = false;

  // ── ISSUE-003 app-wide group selection ─────────────────────────────────────

  SelectedGroupSubscription? _groupSelSub;

  /// Org the subscription is bound to — an ORG switch must rebind.
  String? _groupSelOrgId;

  /// Follow group switches made on ANY other tab (Home / Attendance / Billing /
  /// Exports) so the Master Meal Template and the Weekly / Day-Wise planner
  /// always show the SAME group as the rest of the app. Bound once per org;
  /// the echo of this provider's own [selectGroup] is suppressed by isCurrent.
  void _bindGroupSelection(String organizationId) {
    if (_groupSelSub != null && _groupSelOrgId == organizationId) return;
    _groupSelSub?.cancel();
    _groupSelOrgId = organizationId;
    _groupSelSub = SelectedGroupSubscription.bind(
      organizationId: organizationId,
      isCurrent: (id) => _selectedGroup?.id == id,
      onChanged: (id) {
        // Adopt only a group present in this admin's list — a stale/foreign id
        // is ignored, exactly like the read-time validation on load.
        GroupModel? match;
        for (final g in _groups) {
          if (g.id == id) {
            match = g;
            break;
          }
        }
        if (match == null) return;
        // Repaint the new group's header/toggles in the SAME frame as the
        // switch (no stale group name), then refresh its meals. Deliberately
        // does not re-write the store — the value is already this id.
        _selectedGroup = match;
        _mealsEnabled = match.mealConfig.mealsEnabled;
        _preferencesEnabled = match.mealConfig.preferencesEnabled;
        _mealPricingEnabled = match.mealConfig.mealPricingEnabled;
        notifyListeners();
        unawaited(
          _loadMeals(organizationId: organizationId, groupId: match.id),
        );
      },
    );
  }

  @override
  void dispose() {
    _groupSelSub?.cancel();
    super.dispose();
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;
  List<MealModel> get meals => _meals;

  /// ISSUE-001 (Live-Test-13): the SCHEDULABLE meals — active only.
  ///
  /// [meals] now also carries DISABLED meals so the Master Meal Template can
  /// re-enable them; a disabled meal must never be offered by the planner.
  ///
  /// Memoized on the identity of [_meals] so the filtered list is built ONCE
  /// per data change instead of on every widget build. The planner previously
  /// passed [meals] straight through with zero allocation, and filtering in
  /// `build()` would have re-allocated on every rebuild (and once per day tab)
  /// — this keeps the render path allocation-free, exactly as before.
  List<MealModel>? _activeMealsCache;
  List<MealModel>? _activeMealsSource;
  List<MealModel> get activeMeals {
    if (!identical(_activeMealsSource, _meals)) {
      _activeMealsSource = _meals;
      _activeMealsCache =
          _meals.where((m) => m.isActive).toList(growable: false);
    }
    return _activeMealsCache!;
  }
  List<GroupModel> get groups => _groups;
  GroupModel? get selectedGroup => _selectedGroup;
  MealScheduleModel? get weekSchedule => _weekSchedule;
  bool get mealsEnabled => _mealsEnabled;
  bool get preferencesEnabled => _preferencesEnabled;
  bool get mealPricingEnabled => _mealPricingEnabled;

  /// SRS FR-TRUST-001 (Pass 7): true when the group runs the opt-out trust
  /// model (unmarked members auto-Present at window close). Read straight off
  /// the selected group so it always reflects the last server state.
  bool get optOutAttendance => _selectedGroup?.mealConfig.isOptOut ?? false;

  /// Module 22 (FR-HG-020, Pass 9): the selected group's hosted-guest
  /// settings — read off the group so it always reflects server state.
  GroupGuestConfig get guestConfig =>
      _selectedGroup?.mealConfig.guestConfig ?? const GroupGuestConfig();

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> loadGroups({required String organizationId}) async {
    // ISSUE-003: follow app-wide group switches made on any other tab.
    _bindGroupSelection(organizationId);
    if (_isLoading) return;
    // Cache-first: paint last-known groups instantly, then refresh. Uses the
    // SHARED org-groups key (same endpoint + model as Groups/Attendance/
    // Billing) so ONE fetch from any admin tab warms them all — the old
    // 'meal_config_groups' key duplicated the identical list.
    final cacheKey = 'admin_groups:$organizationId';
    if (_groups.isEmpty) {
      _isLoading = true; // sync: first build shows the loader, never empty state
      // Miss-vs-empty aware: a cached EMPTY org (new account) paints its real
      // empty state instantly; only a true cache MISS keeps the loader.
      final cachedGroups = await ResponseCacheService.instance.readListOrNull(
          cacheKey, GroupModel.fromJson, maxAge: const Duration(hours: 12));
      if (cachedGroups != null) {
        _groups = cachedGroups;
        _isLoading = false;
      }
      // Auto-select the app-wide selected group (ISSUE-003: the SAME group
      // every admin tab follows — SelectedGroupStore), falling back to the
      // first cached group, + paint its cached config/meals so the body never
      // flashes "No groups yet" while groups exist. No network awaited here;
      // the fetch below overwrites.
      if (_selectedGroup == null && _groups.isNotEmpty) {
        final savedId =
            await SelectedGroupStore.instance.read(organizationId);
        final g = _groups.firstWhere(
          (x) => x.id == savedId,
          orElse: () => _groups.first,
        );
        _selectedGroup = g;
        _mealsEnabled = g.mealConfig.mealsEnabled;
        _preferencesEnabled = g.mealConfig.preferencesEnabled;
        _mealPricingEnabled = g.mealConfig.mealPricingEnabled;
        _meals = await ResponseCacheService.instance.readList(
            _mealsCacheKey(organizationId, g.id), MealModel.fromJson,
            maxAge: const Duration(hours: 12));
      }
    } else {
      _isLoading = false;
    }
    _error = null;
    notifyListeners();

    final result = await _groupRepo.getOrganisationGroups(
      organizationId: organizationId,
    );

    switch (result) {
      case Ok(:final value):
        _groups = value.data;
        ResponseCacheService.instance
            .writeList(cacheKey, value.data, (g) => g.toJson());
        // Show the cache-selected group if it still exists, else the app-wide
        // selected group (ISSUE-003), else the first; always refresh its
        // config + meals from the network.
        final selId = _selectedGroup?.id ??
            await SelectedGroupStore.instance.read(organizationId);
        final List<GroupModel> matches = (selId == null)
            ? <GroupModel>[]
            : value.data.where((g) => g.id == selId).toList();
        final GroupModel? toLoad = matches.isNotEmpty
            ? matches.first
            : (value.data.isNotEmpty ? value.data.first : null);
        if (toLoad != null) {
          await _loadForGroup(toLoad, organizationId: organizationId);
        }
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Weekly-Planner boot in ONE parallel network wave (additive; the classic
  /// loadGroups→loadSchedule chain cost 3 sequential round-trips: groups →
  /// meals → schedule — the "planner feels slow" root cause).
  ///
  /// Order of operations is chosen so draft auto-population stays correct:
  /// 1. LOCAL, awaited (all ~ms): cached groups + selection resolve (honouring
  ///    [preferredGroupId] from Meal Config) + cached meals — so [_meals] is
  ///    populated BEFORE any schedule response can reach
  ///    [_ensureWeekdaysPopulated].
  /// 2. PARALLEL network: loadGroups (refreshes groups + selected meals) and
  ///    loadSchedule for the resolved group ride the same wave.
  /// 3. RECONCILE: if the network moved the selection (deleted group /
  ///    late-arriving preferred group), reload the schedule for the final one.
  /// Cold cache (no known group) falls back to today's sequential behaviour.
  Future<void> bootstrapPlanner({
    required String organizationId,
    String? preferredGroupId,
  }) async {
    // 1 — local paint.
    if (_groups.isEmpty) {
      _groups = await ResponseCacheService.instance.readList(
          'admin_groups:$organizationId', GroupModel.fromJson,
          maxAge: const Duration(hours: 12));
    }
    GroupModel? sel;
    if (preferredGroupId != null && preferredGroupId.isNotEmpty) {
      for (final g in _groups) {
        if (g.id == preferredGroupId) {
          sel = g;
          break;
        }
      }
    }
    sel ??= _selectedGroup;
    // ISSUE-003: with no explicit/previous selection, follow the app-wide
    // selected group before falling back to the first.
    if (sel == null && _groups.isNotEmpty) {
      final savedId = await SelectedGroupStore.instance.read(organizationId);
      sel = _groups.firstWhere(
        (g) => g.id == savedId,
        orElse: () => _groups.first,
      );
    }
    if (sel != null) {
      _selectedGroup = sel;
      _mealsEnabled = sel.mealConfig.mealsEnabled;
      _preferencesEnabled = sel.mealConfig.preferencesEnabled;
      _mealPricingEnabled = sel.mealConfig.mealPricingEnabled;
      if (_meals.isEmpty) {
        _meals = await ResponseCacheService.instance.readList(
            _mealsCacheKey(organizationId, sel.id), MealModel.fromJson,
            maxAge: const Duration(hours: 12));
      }
    }
    notifyListeners();

    // 2 — one parallel network wave.
    final selId = sel?.id;
    await Future.wait(<Future<void>>[
      loadGroups(organizationId: organizationId),
      if (selId != null)
        loadSchedule(organizationId: organizationId, groupId: selId),
    ]);

    // 3 — reconcile. Prefer the Meal-Config group if it only arrived with the
    // network list (Issue 1 parity with the old chain), else follow loadGroups'
    // still-exists selection.
    if (preferredGroupId != null &&
        preferredGroupId.isNotEmpty &&
        _selectedGroup?.id != preferredGroupId) {
      for (final g in _groups) {
        if (g.id == preferredGroupId) {
          await _loadForGroup(g, organizationId: organizationId);
          break;
        }
      }
    }
    final finalId = _selectedGroup?.id;
    if (finalId != null && finalId != selId) {
      await loadSchedule(organizationId: organizationId, groupId: finalId);
    } else if (finalId != null) {
      // Late-meals guard: on a cold meals cache the schedule can land before
      // loadGroups fills [_meals], skipping draft auto-population. Re-run it —
      // it's a strict no-op when published or already populated.
      await _ensureWeekdaysPopulated(finalId);
      notifyListeners();
    }
  }

  Future<void> selectGroup(
    GroupModel group, {
    required String organizationId,
  }) async {
    _selectedGroup = group;
    _mealsEnabled = group.mealConfig.mealsEnabled;
    _preferencesEnabled = group.mealConfig.preferencesEnabled;
    _mealPricingEnabled = group.mealConfig.mealPricingEnabled;
    // ISSUE-003: an explicit switch here IS the app-wide selection now.
    unawaited(SelectedGroupStore.instance.write(organizationId, group.id));
    notifyListeners();
    await _loadMeals(
      organizationId: organizationId,
      groupId: group.id,
    );
  }

  Future<void> _loadForGroup(
    GroupModel group, {
    required String organizationId,
  }) async {
    _selectedGroup = group;
    _mealsEnabled = group.mealConfig.mealsEnabled;
    _preferencesEnabled = group.mealConfig.preferencesEnabled;
    _mealPricingEnabled = group.mealConfig.mealPricingEnabled;
    await _loadMeals(
      organizationId: organizationId,
      groupId: group.id,
    );
  }

  /// Per-org, per-group cache key for the configured meals list.
  String _mealsCacheKey(String orgId, String groupId) =>
      'meal_config_meals:$orgId:$groupId';

  /// Write-through: persist the current [_meals] so the next open of this group
  /// paints instantly. Called after load AND every mutation, so the cache never
  /// goes stale relative to what the admin just changed.
  void _cacheMeals(String orgId, String groupId) {
    ResponseCacheService.instance
        .writeList(_mealsCacheKey(orgId, groupId), _meals, (m) => m.toJson());
  }

  Future<void> _loadMeals({
    required String organizationId,
    required String groupId,
  }) async {
    // Cache-first (SWR): paint the last-known meals for this group instantly,
    // then refresh below. The network result always overwrites.
    if (_meals.isEmpty) {
      _meals = await ResponseCacheService.instance.readList(
          _mealsCacheKey(organizationId, groupId), MealModel.fromJson,
          maxAge: const Duration(hours: 12));
      if (_meals.isNotEmpty) notifyListeners();
    }
    // Miss-vs-empty note: a cached-empty list is indistinguishable from a
    // miss here, but this method never gates a loader on it — the screen
    // stays interactive while the refresh below reconciles.

    final result = await _mealRepo.getGroupMeals(
      organizationId: organizationId,
      groupId: groupId,
      // ISSUE-001 (Live-Test-13): the Master Meal Template MUST see disabled
      // meals — its card already renders them dimmed with an "Enable" button,
      // and the active-meal cap counter already excludes them. Without this a
      // disabled meal vanished from the list, so it could never be turned back
      // on (indistinguishable from a delete). Consumers that must not offer a
      // disabled meal (planner grid, auto-populate) filter on isActive.
      includeDisabled: true,
    );

    switch (result) {
      case Ok(:final value):
        // FR-MEAL-007 (ISSUE-18): chronological by attendance-window open
        // time, admin order as tie-breaker — consistent across all screens.
        _meals = List.of(value)
          ..sort(MealModel.compareChronological);
        _cacheMeals(organizationId, groupId);
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
    // SRS Module 03 SCH-011/012: the recurring toggle + its cached template
    // were removed — server-side auto-continuation keeps serving the last
    // PUBLISHED schedule; this only default-populates a brand-new empty draft.
    _defaultPopulateWeek();
  }

  // SRS Module 03 SCH-011/012: the "Continue Recurring Weekly Menu" toggle,
  // its SharedPreferences flag and cached-template machinery were permanently
  // REMOVED — auto-continuation is server-side, always on, with no toggle.

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
    int? price,
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
      price: price,
    );

    switch (result) {
      case Ok(:final value):
        _meals = [..._meals, value]
          ..sort(MealModel.compareChronological);
        _cacheMeals(organizationId, groupId);
        // Seed the image cache with the bytes we just uploaded so the new meal
        // photo renders instantly under its new URL (no CDN re-download).
        if (safeImages.isNotEmpty) {
          ImageCacheSeeder.seed(value.imageUrl, safeImages.first);
        }
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
    int? price,
  }) async {
    _isSaving = true;
    _error = null;

    // ISSUE-004: a pure Enable/Disable flip paints OPTIMISTICALLY — the
    // switch moves on the tap itself and rolls back only on failure. Config
    // edits carrying other fields keep the confirmed round-trip behaviour.
    List<MealModel>? prevMeals;
    final isPureToggle = isActive != null &&
        name == null &&
        description == null &&
        menuItems == null &&
        availablePreferences == null &&
        attendanceWindow == null &&
        imageBytes == null &&
        price == null;
    if (isPureToggle) {
      final idx = _meals.indexWhere((m) => m.id == mealId);
      if (idx != -1) {
        prevMeals = _meals;
        _meals = List.of(_meals)
          ..[idx] = _meals[idx].copyWith(isActive: isActive);
      }
    }
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
      price: price,
    );

    switch (result) {
      case Ok(:final value):
        final idx = _meals.indexWhere((m) => m.id == mealId);
        if (idx != -1) {
          _meals = List.of(_meals)..[idx] = value;
        }
        _cacheMeals(organizationId, groupId);
        // Seed the image cache with the bytes we just uploaded so the replaced
        // meal photo renders instantly under its new URL (no CDN re-download).
        final seedBytes = safeImages ?? imageBytes;
        if (seedBytes != null && seedBytes.isNotEmpty) {
          ImageCacheSeeder.seed(value.imageUrl, seedBytes.first);
        }
        _isSaving = false;
        notifyListeners();
        return true;
      case Err(:final failure):
        // ISSUE-004: roll the optimistic Enable/Disable flip back — the UI
        // must never claim an unsaved state.
        if (prevMeals != null) _meals = prevMeals;
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
        _cacheMeals(organizationId, groupId);
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return false;
    }
  }

  // ── Toggles ───────────────────────────────────────────────────────────────

  /// Live-Test-8 ISSUE-003: ONE optimistic mealConfig patch used by every
  /// toggle. The switch reflects the tap INSTANTLY (local state + notify
  /// before the network), then the server's authoritative group replaces it;
  /// on failure the exact previous state is restored and the error surfaced.
  /// This is what turns the old "tap → nothing → tap again" round-trip lag
  /// into a single smooth flip.
  /// ISSUE-004 (Live-Test-12): patches are SERIALIZED through this chain so
  /// rapid consecutive toggle taps never race each other on the wire, while
  /// the UI stays fully interactive (switches are no longer disabled during a
  /// save). Each tap composes onto the latest optimistic state; because every
  /// patch carries the FULL mealConfig, the LAST request fully determines the
  /// server state — an earlier failure is self-healed by the next patch.
  Future<void> _patchQueue = Future.value();
  int _patchSeq = 0;

  Future<bool> _patchMealConfigOptimistic({
    required String organizationId,
    required String groupId,
    required GroupMealConfig updatedConfig,
    void Function(GroupModel serverGroup)? onSaved,
  }) async {
    if (_selectedGroup == null) return false;
    final prevGroup = _selectedGroup!;
    final prevMealsEnabled = _mealsEnabled;
    final prevPrefs = _preferencesEnabled;
    final prevPricing = _mealPricingEnabled;

    // Optimistic paint — the tapped switch moves on the tap itself.
    _selectedGroup = prevGroup.copyWith(mealConfig: updatedConfig);
    _mealsEnabled = updatedConfig.mealsEnabled;
    _preferencesEnabled = updatedConfig.preferencesEnabled;
    _mealPricingEnabled = updatedConfig.mealPricingEnabled;
    _isSaving = true;
    notifyListeners();

    // ISSUE-004: ride the serialized queue; only the NEWEST patch applies
    // server truth / reverts, so an in-flight response can never clobber a
    // later optimistic flip.
    final mySeq = ++_patchSeq;
    final completer = Completer<bool>();
    _patchQueue = _patchQueue.then((_) async {
      final result = await _groupRepo.updateGroup(
        organizationId: organizationId,
        groupId: groupId,
        mealConfig: updatedConfig,
      );

      final isNewest = mySeq == _patchSeq;
      switch (result) {
        case Ok(:final value):
          if (isNewest) {
            // Server truth wins (it may cascade flags — ATT-007 exclusivity).
            _selectedGroup = value;
            _mealsEnabled = value.mealConfig.mealsEnabled;
            _preferencesEnabled = value.mealConfig.preferencesEnabled;
            _mealPricingEnabled = value.mealConfig.mealPricingEnabled;
            _isSaving = false;
          }
          onSaved?.call(value);
          notifyListeners();
          completer.complete(true);
        case Err(:final failure):
          if (isNewest) {
            // Revert — the UI must never claim an unsaved state. (A stale
            // failure needs no revert: the newer queued patch re-sends the
            // full config and resolves the truth.)
            _selectedGroup = prevGroup;
            _mealsEnabled = prevMealsEnabled;
            _preferencesEnabled = prevPrefs;
            _mealPricingEnabled = prevPricing;
            _error = failure.message;
            _isSaving = false;
            notifyListeners();
          }
          completer.complete(false);
      }
    }).catchError((_) {
      if (!completer.isCompleted) completer.complete(false);
    });
    return completer.future;
  }

  Future<bool> toggleMealSystem({
    required String organizationId,
    required String groupId,
    required bool enabled,
  }) async {
    if (_selectedGroup == null) return false;
    // Live-Test-8 ISSUE-003: master toggle — the server preserves the stored
    // sub-flags while meals are OFF (they are gated, not cleared), so
    // re-enabling restores the admin's prior configuration exactly.
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(
        mealsEnabled: enabled,
      ),
    );
  }

  Future<bool> togglePreferences({
    required String organizationId,
    required String groupId,
    required bool enabled,
    List<MealPreferenceOption>? enabledPreferences,
  }) async {
    if (_selectedGroup == null) return false;
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(
        preferencesEnabled: enabled,
        enabledPreferences: enabledPreferences ??
            _selectedGroup!.mealConfig.enabledPreferences,
      ),
      onSaved: (_) {
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
      },
    );
  }

  /// SRS FR-TRUST-001 (Pass 7): switch the group between opt-in ('absent',
  /// legacy) and opt-out ('present') attendance defaults. Server audits the
  /// flip and the sweep worker starts/stops materializing system defaults.
  /// ATT-007: the server may auto-disable Meal Preferences when Auto-Present
  /// turns on — the optimistic helper mirrors the authoritative response.
  Future<bool> setAttendanceDefault({
    required String organizationId,
    required String groupId,
    required bool optOut,
  }) async {
    if (_selectedGroup == null) return false;
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(
        attendanceDefault: optOut ? 'present' : 'absent',
      ),
    );
  }

  /// Additive: toggle the per-group meal pricing setting. When OFF, price UI
  /// disappears everywhere; when ON, price fields appear in master/planner/student.
  Future<bool> toggleMealPricing({
    required String organizationId,
    required String groupId,
    required bool enabled,
  }) async {
    if (_selectedGroup == null) return false;
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(
        mealPricingEnabled: enabled,
      ),
    );
  }

  /// SRS Module 03 (survey Q17/Q22) + Live-Test-8 ISSUE-005: "Bill Skip"
  /// policy — when ON, unmarked (no-response) meals get a system-generated
  /// Skip at window-close billed at the scheduled price, date-forward only
  /// (never affects past bills). Absent billing is governed by the separate
  /// Bill-Absent toggle (ISSUE-017). Kitchen counts stay Present-only.
  Future<bool> toggleBillSkippedMeals({
    required String organizationId,
    required String groupId,
    required bool enabled,
  }) async {
    if (_selectedGroup == null) return false;
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(
        billSkippedMeals: enabled,
      ),
    );
  }

  /// Live-Test-11 ISSUE-017 (survey-locked): independent "Bill Absent Meals"
  /// policy — when ON, meals marked Absent bill at the scheduled price,
  /// DATE-FORWARD only: the server snapshots the policy onto each absent
  /// record at mark time, so flipping the toggle never rewrites past bills.
  /// Fully independent from Bill-Skip.
  Future<bool> toggleBillAbsentMeals({
    required String organizationId,
    required String groupId,
    required bool enabled,
  }) async {
    if (_selectedGroup == null) return false;
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(
        billAbsentMeals: enabled,
      ),
    );
  }

  /// Pass 11 (FR-VACX-001): approval-gated vacation — when ON, members must
  /// submit a dated request; the instant toggle is refused server-side.
  Future<bool> setVacationRequiresApproval({
    required String organizationId,
    required String groupId,
    required bool enabled,
  }) async {
    if (_selectedGroup == null) return false;
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(
        vacationRequiresApproval: enabled,
      ),
    );
  }

  /// Pass 12 (FR-BILLX-020): billing cycle start day (1–28; day 1 = calendar
  /// month). Audited server-side like every other policy flip (LOOP-033).
  Future<bool> setBillingCycleStartDay({
    required String organizationId,
    required String groupId,
    required int day,
  }) async {
    if (_selectedGroup == null) return false;
    _isSaving = true;
    notifyListeners();

    final updatedConfig =
        _selectedGroup!.mealConfig.copyWith(billingCycleStartDay: day);

    final result = await _groupRepo.updateGroup(
      organizationId: organizationId,
      groupId: groupId,
      mealConfig: updatedConfig,
    );

    switch (result) {
      case Ok(:final value):
        _selectedGroup = value;
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

  /// Module 22 (FR-HG-020/021, Pass 9): persist the hosted-guest settings.
  /// Rides the same mealConfig PATCH as every other group toggle; the backend
  /// validates cross-field rules against the FINAL effective state
  /// (GUESTS_REQUIRE_MEALS / GUEST_PRICE_REQUIRED / GUEST_SURCHARGE_REQUIRED).
  Future<bool> updateGuestConfig({
    required String organizationId,
    required String groupId,
    required GroupGuestConfig config,
  }) async {
    if (_selectedGroup == null) return false;
    return _patchMealConfigOptimistic(
      organizationId: organizationId,
      groupId: groupId,
      updatedConfig: _selectedGroup!.mealConfig.copyWith(guestConfig: config),
    );
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

  /// Issue 2: when the backend rejects a publish/edit because the schedule is
  /// ALREADY published (local state optimistically flipped to draft after an
  /// edit, desyncing from the server), sync the local copy back to published.
  /// This makes the green "Published" banner and the "Revert to Draft" menu
  /// appear immediately, instead of needing a navigate-away-and-back reload.
  void _syncPublishedIfServerRejected(String? message) {
    final sched = _weekSchedule;
    if (sched == null || sched.isPublished) return;
    if ((message ?? '').toLowerCase().contains('publish')) {
      _weekSchedule = sched.copyWith(isPublished: true);
    }
  }

  /// Live-Test-16 ISSUE-1: mirror the lock the SERVER just established by
  /// accepting this group's first schedule publication, so the Meal Config
  /// screen renders its 🔒 state immediately.
  ///
  /// This is a state sync, not a guess: it runs only after a publish that
  /// actually succeeded, and the backend remains the sole authority (it rejects
  /// any locked flip regardless of what this flag says). Local-only, so the
  /// screen never pays an extra network wave for it.
  void markMealPricingLocked({required String organizationId}) {
    final group = _selectedGroup;
    if (group == null || group.mealConfig.mealPricingLocked) return;
    final locked = group.copyWith(
      mealConfig: group.mealConfig.copyWith(mealPricingLocked: true),
    );
    _selectedGroup = locked;
    // Keep the in-memory list in step so the group selector agrees.
    final i = _groups.indexWhere((g) => g.id == locked.id);
    if (i >= 0) _groups[i] = locked;
    notifyListeners();

    // Shared-key write-through (guidebook §2): `admin_groups:{org}` is read by
    // EVERY admin tab's group selector. Without this, a cache-first paint after
    // an app restart would show the pricing toggle as still editable until the
    // network refresh landed. Fire-and-forget with an internal catch — cache
    // repair is best-effort and the next groups load rewrites the truth.
    unawaited(() async {
      try {
        final key = 'admin_groups:$organizationId';
        final cached = await ResponseCacheService.instance
            .readListOrNull(key, GroupModel.fromJson);
        if (cached == null) return;
        var changed = false;
        final next = <GroupModel>[];
        for (final g in cached) {
          if (g.id == locked.id && !g.mealConfig.mealPricingLocked) {
            changed = true;
            next.add(locked);
          } else {
            next.add(g);
          }
        }
        if (changed) {
          ResponseCacheService.instance.writeList(key, next, (g) => g.toJson());
        }
      } catch (_) {
        // Best-effort only — never let cache repair surface to the admin.
      }
    }());
  }

  Future<bool> publishSchedule({
    required String organizationId,
    required String groupId,
  }) async {
    if (_weekSchedule == null) return false;
    _isSaving = true;
    notifyListeners();

    String scheduleId = _weekSchedule!.id;
    final bool isNew = scheduleId.isEmpty;

    // Issue #12: a locally-built draft has an empty id — create it first so
    // publish targets a real /schedules/:id. An existing week is NOT pre-updated
    // (that path was rejected for published weeks); instead its entries are sent
    // straight to publish for an atomic replace-and-publish (Issue 2), so
    // students never lose the live published week while the admin edits.
    if (isNew) {
      final saveResult = await _mealRepo.saveSchedule(
        organizationId: organizationId,
        groupId: groupId,
        schedule: _weekSchedule!,
      );
      switch (saveResult) {
        case Ok(:final value):
          _weekSchedule = value;
          scheduleId = value.id;
        case Err(:final failure):
          _error = failure.message;
          _syncPublishedIfServerRejected(failure.message);
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
    }

    final result = await _mealRepo.publishSchedule(
      organizationId: organizationId,
      groupId: groupId,
      scheduleId: scheduleId,
      // Existing week -> send entries for atomic replace+publish. New week was
      // just created with its entries, so a plain flag-flip publish suffices.
      schedule: isNew ? null : _weekSchedule,
    );

    switch (result) {
      case Ok(:final value):
        _weekSchedule = value;
        _isSaving = false;
        notifyListeners();
        return true;
      case Err(:final failure):
        _error = failure.message;
        _syncPublishedIfServerRejected(failure.message);
        _isSaving = false;
        notifyListeners();
        return false;
    }
  }

  /// Issue 2: revert a PUBLISHED schedule back to draft so the admin can edit
  /// and re-publish. No-op when there is no persisted schedule (empty id).
  ///
  /// Pass 15 (FR-SCHX-003): [hide]=true is a FULL unpublish — the week is
  /// hidden from students while the draft/snapshot stay recoverable. Default
  /// false is the legacy keep-visible edit-mode revert (unchanged behaviour).
  Future<bool> revertToDraft({
    required String organizationId,
    required String groupId,
    bool hide = false,
  }) async {
    final scheduleId = _weekSchedule?.id ?? '';
    if (scheduleId.isEmpty) return false;
    _isSaving = true;
    notifyListeners();

    final result = await _mealRepo.revertSchedule(
      organizationId: organizationId,
      groupId: groupId,
      scheduleId: scheduleId,
      hide: hide,
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

  /// FR-MEAL-007 (ISSUE-18): chronological comparator for planner day entries.
  /// Effective open time = per-day override ?? master meal template window;
  /// entries without a resolvable window sort last; admin order tie-break.
  int _compareEntriesChronological(DayMealEntry a, DayMealEntry b) {
    final ak = _entryChronoKey(a);
    final bk = _entryChronoKey(b);
    if (ak != bk) return ak.compareTo(bk);
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.mealId.compareTo(b.mealId);
  }

  int _entryChronoKey(DayMealEntry e) {
    final override = e.openTime;
    if (override != null && override.isNotEmpty) {
      return MealModel.chronoMinutes(override);
    }
    for (final m in _meals) {
      if (m.id == e.mealId) return m.chronoKey;
    }
    return 24 * 60;
  }

  /// Default-populates an EMPTY draft: every active meal enabled on every day
  /// with its template menu items. (SCH-012 note: this is NOT the removed
  /// "Copy from previous week" action — it only seeds a brand-new draft.)
  void _defaultPopulateWeek() {
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
                price: m.price,
              ))
          .toList()
        ..sort(_compareEntriesChronological);
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
    List<String>? enabledPreferenceGroupIds,
    int? price,
    bool clearPrice = false,
    String? description,
    bool clearDescription = false,
    List<Uint8List>? imageBytes,
  }) {
    if (_weekSchedule == null) return;

    final updatedDays = _weekSchedule!.days.map((daySchedule) {
      if (daySchedule.day != day) return daySchedule;

      final updatedMeals = daySchedule.meals.map((entry) {
        if (entry.mealId != mealId) return entry;
        // Persist the per-day photo as a base64 data URI in imageUrl (one image
        // per entry, replaced on each edit). Empty list = photo removed → null
        // (the meal then inherits the master photo). null param = untouched.
        final String? nextImageUrl = imageBytes == null
            ? entry.imageUrl
            : (imageBytes.isEmpty
                ? null
                : 'data:image/jpeg;base64,${base64Encode(imageBytes.first)}');
        return DayMealEntry(
          mealId: entry.mealId,
          name: name ?? entry.name,
          slotKey: entry.slotKey,
          order: entry.order,
          menuItems: menuItems ?? entry.menuItems,
          imageUrl: nextImageUrl,
          description:
              clearDescription ? null : (description ?? entry.description),
          imageBytes: imageBytes ?? entry.imageBytes,
          openTime: openTime ?? entry.openTime,
          closeTime: closeTime ?? entry.closeTime,
          preferencesEnabled: preferencesEnabled ?? entry.preferencesEnabled,
          enabledPreferences: enabledPreferences ?? entry.enabledPreferences,
          enabledPreferenceGroupIds:
              enabledPreferenceGroupIds ?? entry.enabledPreferenceGroupIds,
          price: clearPrice ? null : (price ?? entry.price),
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

      // Live-Test-11 ISSUE-007: guaranteed-fit ladder (resolution + quality),
      // matching the form's picker — the provider guard can no longer reject
      // a photo the ladder could have fitted.
      final result = await compressImageToBudget(bytes, cap ~/ raw.length);
      if (result != null && result.isNotEmpty) compressed.add(result);
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

    // Build a fresh day entry from the master meal template.
    DayMealEntry buildEntry() {
      final meal = _meals.firstWhere(
        (m) => m.id == mealId,
        orElse: () => _meals.first,
      );
      return DayMealEntry(
        mealId: meal.id,
        name: meal.name,
        slotKey: meal.slotKey,
        order: meal.order,
        // Copy menu items from the template so the newly-enabled day
        // entry starts with the same content as the shared meal.
        menuItems: List<String>.from(meal.menuItems),
        preferencesEnabled: meal.preferencesEnabled,
        enabledPreferences: meal.enabledPreferences,
        price: meal.price,
      );
    }

    final bool dayExists =
        _weekSchedule!.days.any((d) => d.day == targetDay);

    List<DaySchedule> updatedDays;
    if (!dayExists) {
      // Regression fix: a weekday with NO day-row (all meals disabled, or a
      // published week that only stored enabled days) must still be enable-able.
      // Previously toggleMealDay only mutated EXISTING day-rows, so enabling a
      // meal on such a day silently did nothing. Create the day on enable.
      if (!enabled) return; // nothing to disable on a non-existent day
      updatedDays = [
        ..._weekSchedule!.days,
        DaySchedule(day: targetDay, meals: [buildEntry()]),
      ];
    } else {
      updatedDays = _weekSchedule!.days.map((daySchedule) {
        if (daySchedule.day != targetDay) return daySchedule;

        final List<DayMealEntry> entries =
            List<DayMealEntry>.from(daySchedule.meals);
        if (enabled) {
          if (!entries.any((e) => e.mealId == mealId)) {
            entries.add(buildEntry());
            entries.sort(_compareEntriesChronological);
          }
        } else {
          entries.removeWhere((e) => e.mealId == mealId);
        }
        return DaySchedule(day: daySchedule.day, meals: entries);
      }).toList();
    }

    _weekSchedule = MealScheduleModel(
      id: _weekSchedule!.id,
      groupId: _weekSchedule!.groupId,
      organizationId: _weekSchedule!.organizationId,
      days: updatedDays,
      // Editing always reverts to a local draft (consistent with every other
      // edit method) so the change is editable + a Publish button appears. The
      // SERVER's published schedule stays live for students until re-publish.
      isPublished: false,
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
              enabledPreferenceGroupIds:
                  List<String>.from(e.enabledPreferenceGroupIds),
              price: e.price,
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

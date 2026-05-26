import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/data/contracts/i_event_repository.dart';
import 'package:smart_meal_management/data/repositories/event_repository.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_meal_type.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/features/events/models/guest_person.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

// ── EventAdminProvider ─────────────────────────────────────────────────────────

/// Manages state for the event admin experience.
///
/// Covers:
///   1. Landing mode — all events for this admin (loadMyEvents, createEvent).
///   2. Event mode — a specific event + parties + meal type CRUD.
///
/// Accepts [IEventRepository] so the real [ApiEventRepository] can be
/// injected for staging/production without changing provider logic.
class EventAdminProvider extends ChangeNotifier {
  /// Defaults to [EventRepository] which internally dispatches to mock or live
  /// based on [EnvConfig.current.mockAuthEnabled].
  EventAdminProvider({IEventRepository? repo})
      : _repo = repo ?? EventRepository();

  final IEventRepository _repo;

  // ── State ─────────────────────────────────────────────────────────────────

  List<EventModel> _myEvents = [];
  bool _isLoadingEvents = false;

  EventModel? _event;
  List<EventGuestParty> _parties = [];
  bool _isLoading = false;
  String? _error;

  // ── Public getters — landing ──────────────────────────────────────────────

  List<EventModel> get myEvents => List.unmodifiable(_myEvents);
  bool get isLoadingEvents => _isLoadingEvents;

  // ── Public getters — event ────────────────────────────────────────────────

  EventModel? get event => _event;
  List<EventGuestParty> get parties => List.unmodifiable(_parties);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Aggregate counts ──────────────────────────────────────────────────────

  int get totalGuestCount =>
      _parties.fold(0, (s, p) => s + p.totalCount);

  int get totalAdultCount =>
      _parties.fold(0, (s, p) => s + p.adultsCount);

  int get totalChildCount =>
      _parties.fold(0, (s, p) => s + p.childrenCount);

  int get totalPartyCount => _parties.length;

  /// Guests with no event meal type selected.
  int get pendingMealCount => _parties
      .expand((p) => p.persons)
      .where((person) => person.selectedMealTypeId == null && person.isPresent)
      .length;

  /// Flat list of all persons across all parties.
  List<GuestPerson> get allPersons =>
      _parties.expand((p) => p.persons).toList();

  // ── Meal-type-wise analytics ──────────────────────────────────────────────

  /// Per meal-type breakdown: total, adult, child counts.
  ///
  /// Only counts persons who are [isPresent].
  Map<String, ({int total, int adults, int children})>
      get mealTypeBreakdown {
    final result = <String, ({int total, int adults, int children})>{};
    for (final party in _parties) {
      for (final person in party.persons) {
        if (!person.isPresent) continue;
        final id = person.selectedMealTypeId;
        if (id == null) continue;
        final prev = result[id] ??
            (total: 0, adults: 0, children: 0);
        result[id] = (
          total: prev.total + 1,
          adults: prev.adults + (person.isAdult ? 1 : 0),
          children: prev.children + (person.isAdult ? 0 : 1),
        );
      }
    }
    return result;
  }

  /// Total veg count (based on EventMealType.isVeg).
  int get totalVegCount {
    if (_event == null) return 0;
    final vegIds = _event!.mealTypes
        .where((m) => m.isVeg)
        .map((m) => m.id)
        .toSet();
    return allPersons
        .where((p) => p.isPresent && vegIds.contains(p.selectedMealTypeId))
        .length;
  }

  /// Total non-veg count.
  int get totalNonVegCount {
    if (_event == null) return 0;
    final nonVegIds = _event!.mealTypes
        .where((m) => !m.isVeg)
        .map((m) => m.id)
        .toSet();
    return allPersons
        .where((p) =>
            p.isPresent && nonVegIds.contains(p.selectedMealTypeId))
        .length;
  }

  // ── Landing mode ──────────────────────────────────────────────────────────

  Future<void> loadMyEvents({required String adminId}) async {
    _isLoadingEvents = true;
    _error = null;
    notifyListeners();

    final result = await _repo.getEventsByAdmin(adminId);
    switch (result) {
      case Ok(:final value):
        _myEvents = value;
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoadingEvents = false;
    notifyListeners();
  }

  Future<EventModel?> createEvent({
    required String name,
    required EventType type,
    required DateTime date,
    required int expectedGuestCount,
    required String adminId,
    required String adminName,
    required bool autoDeleteAfter7Days,
  }) async {
    // In mock/dev mode, generate a client-side join code so the event is
    // immediately usable without a backend. In live mode, pass null — the
    // server assigns the join code and returns it in the response.
    final clientJoinCode =
        EnvConfig.current.mockAuthEnabled ? _generateJoinCode() : null;

    final newEvent = EventModel(
      id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: type,
      date: date,
      expectedGuestCount: expectedGuestCount,
      adminId: adminId,
      adminName: adminName,
      mealTypes: const [],
      autoDeleteAfter7Days: autoDeleteAfter7Days,
      isActive: true,
      createdAt: DateTime.now(),
      joinCode: clientJoinCode,
    );

    final result = await _repo.createEvent(newEvent);
    switch (result) {
      case Ok(:final value):
        _myEvents = [value, ..._myEvents];
        notifyListeners();
        return value;
      case Err(:final failure):
        _error = failure.message;
        notifyListeners();
        return null;
    }
  }

  // ── Event mode ────────────────────────────────────────────────────────────

  Future<void> loadEvent(String eventId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final eventResult = await _repo.getEvent(eventId);
    switch (eventResult) {
      case Ok(:final value):
        _event = value;
      case Err(:final failure):
        _error = failure.message;
        _isLoading = false;
        notifyListeners();
        return;
    }

    final partiesResult = await _repo.getPartiesForEvent(eventId);
    switch (partiesResult) {
      case Ok(:final value):
        _parties = value.toList();
      case Err(:final failure):
        _error = failure.message;
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── Meal type CRUD ────────────────────────────────────────────────────────

  Future<void> addMealType(EventMealType mealType) async {
    if (_event == null) return;
    final idSuffix = DateTime.now().millisecondsSinceEpoch;
    final newType = mealType.id.startsWith('_preset_')
        ? EventMealType(
            id: 'mt_${mealType.title.toLowerCase()}_$idSuffix',
            title: mealType.title,
            emoji: mealType.emoji,
            color: mealType.color,
            isVeg: mealType.isVeg,
          )
        : mealType;

    final updated = _event!.copyWith(
      mealTypes: [..._event!.mealTypes, newType],
    );
    _event = updated;
    notifyListeners();
    // Optimistic — ignore result for fire-and-forget update
    await _repo.updateEvent(updated);
  }

  Future<void> removeMealType(String mealTypeId) async {
    if (_event == null) return;
    final updated = _event!.copyWith(
      mealTypes:
          _event!.mealTypes.where((m) => m.id != mealTypeId).toList(),
    );
    _event = updated;
    notifyListeners();
    await _repo.updateEvent(updated);
  }

  Future<void> updateMealType(EventMealType mealType) async {
    if (_event == null) return;
    final updated = _event!.copyWith(
      mealTypes: _event!.mealTypes
          .map((m) => m.id == mealType.id ? mealType : m)
          .toList(),
    );
    _event = updated;
    notifyListeners();
    await _repo.updateEvent(updated);
  }

  // ── Guest management ──────────────────────────────────────────────────────

  Future<bool> renameGuest({
    required String partyId,
    required String personId,
    required String newName,
  }) async {
    final idx = _parties.indexWhere((p) => p.id == partyId);
    if (idx == -1) return false;
    // Optimistic update
    _parties[idx] = _parties[idx].renamePerson(personId, newName);
    notifyListeners();
    await _repo.updateGuestName(
        partyId: partyId, personId: personId, newName: newName);
    return true;
  }

  Future<bool> setGuestMealPreference({
    required String partyId,
    required String personId,
    required MealPreferenceOption preference,
  }) async {
    final idx = _parties.indexWhere((p) => p.id == partyId);
    if (idx == -1) return false;
    _parties[idx] = _parties[idx].setMealPreference(personId, preference);
    notifyListeners();
    await _repo.updateMealPreference(
        partyId: partyId, personId: personId, preference: preference);
    return true;
  }

  Future<bool> setGuestEventMealType({
    required String partyId,
    required String personId,
    required String? mealTypeId,
  }) async {
    final idx = _parties.indexWhere((p) => p.id == partyId);
    if (idx == -1) return false;
    _parties[idx] = _parties[idx].setEventMealTypeId(personId, mealTypeId);
    notifyListeners();
    await _repo.updateEventMealTypeId(
        partyId: partyId, personId: personId, mealTypeId: mealTypeId);
    return true;
  }

  Future<bool> removeParty(String partyId) async {
    final before = _parties.length;
    _parties.removeWhere((p) => p.id == partyId);
    if (_parties.length != before) {
      notifyListeners();
      await _repo.removeParty(partyId);
      return true;
    }
    return false;
  }

  // ── Event settings ────────────────────────────────────────────────────────

  Future<void> closeEvent() async {
    if (_event == null) return;
    final result = await _repo.deactivateEvent(_event!.id);
    if (result.isOk) {
      _event = _event!.copyWith(isActive: false);
      notifyListeners();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = DateTime.now().millisecondsSinceEpoch;
    final code = StringBuffer();
    var seed = rng;
    for (var i = 0; i < 6; i++) {
      code.write(chars[seed % chars.length]);
      seed ~/= chars.length;
      if (seed == 0) seed = rng + i + 1;
    }
    return code.toString();
  }
}

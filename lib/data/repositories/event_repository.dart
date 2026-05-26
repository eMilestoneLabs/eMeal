import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_event_repository.dart';
import 'package:smart_meal_management/data/mock/mock_events_data.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

// ── EventRepository (dual-mode dispatcher) ────────────────────────────────────

/// Dual-mode event repository — delegates to [MockEventRepository] when
/// [EnvConfig.current.mockAuthEnabled] is true, otherwise returns PHASE_B6
/// stubs until the NestJS backend is integrated.
///
/// Providers should depend on [EventRepository] (not [MockEventRepository])
/// so that the live-mode switch requires only a single edit inside this class.
///
/// PHASE_B6: replace each stub with a real [DioApiService] call.
class EventRepository implements IEventRepository {
  static bool get _isMock => EnvConfig.current.mockAuthEnabled;
  final _mock = MockEventRepository();

  static const _kNotYetWired = NetworkFailure(
    message: 'Live API integration not yet wired. Enable mock mode for development.',
  );

  @override
  Future<Result<EventModel>> getEvent(String eventId) =>
      _isMock ? _mock.getEvent(eventId) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<EventModel>> getEventByJoinCode(String joinCode) =>
      _isMock ? _mock.getEventByJoinCode(joinCode) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<EventModel>> createEvent(EventModel event) =>
      _isMock ? _mock.createEvent(event) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<Unit>> updateEvent(EventModel event) =>
      _isMock ? _mock.updateEvent(event) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<Unit>> deactivateEvent(String eventId) =>
      _isMock ? _mock.deactivateEvent(eventId) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<List<EventModel>>> getEventsByAdmin(String adminId) =>
      _isMock ? _mock.getEventsByAdmin(adminId) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<EventGuestParty>> joinEvent(EventGuestParty party) =>
      _isMock ? _mock.joinEvent(party) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<List<EventGuestParty>>> getPartiesForEvent(String eventId) =>
      _isMock ? _mock.getPartiesForEvent(eventId) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<Unit>> updateGuestName({
    required String partyId,
    required String personId,
    required String newName,
  }) => _isMock
      ? _mock.updateGuestName(partyId: partyId, personId: personId, newName: newName)
      : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<Unit>> updateMealPreference({
    required String partyId,
    required String personId,
    required MealPreferenceOption preference,
  }) => _isMock
      ? _mock.updateMealPreference(partyId: partyId, personId: personId, preference: preference)
      : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<Unit>> updateEventMealTypeId({
    required String partyId,
    required String personId,
    required String? mealTypeId,
  }) => _isMock
      ? _mock.updateEventMealTypeId(partyId: partyId, personId: personId, mealTypeId: mealTypeId)
      : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<Unit>> removeParty(String partyId) =>
      _isMock ? _mock.removeParty(partyId) : Future.value(const Err(_kNotYetWired));

  @override
  Future<Result<Map<String, int>>> getAttendanceSummary(String eventId) =>
      _isMock ? _mock.getAttendanceSummary(eventId) : Future.value(const Err(_kNotYetWired));
}

// ── MockEventRepository ────────────────────────────────────────────────────────

/// Mock implementation of [IEventRepository].
///
/// Uses **static** maps so all instances within a session share the same
/// in-memory store. This lets [EventCreateScreen] write via one provider and
/// [EventAdminShell] read via another without losing data.
///
/// All methods return [Result<T>] — consistent with the rest of the project.
/// Replace this with [ApiEventRepository] when the NestJS backend is ready.
class MockEventRepository implements IEventRepository {
  // ── Shared session state ───────────────────────────────────────────────────

  static final Map<String, EventModel> _events = {};
  static final Map<String, List<EventGuestParty>> _parties = {};
  static bool _seeded = false;

  MockEventRepository() {
    if (_seeded) return;
    _seeded = true;
    for (final event in MockEventsData.adminEvents) {
      _events[event.id] = event;
      _parties[event.id] = MockEventsData.partiesForEvent(event.id);
    }
  }

  static void resetForTesting() {
    _events.clear();
    _parties.clear();
    _seeded = false;
  }

  // ── Event CRUD ─────────────────────────────────────────────────────────────

  @override
  Future<Result<EventModel>> getEvent(String eventId) async {
    await _delay();
    final event = _events[eventId];
    if (event == null) {
      return const Err(NetworkFailure(
        message: 'Event not found.',
        statusCode: 404,
      ));
    }
    return Ok(event);
  }

  @override
  Future<Result<EventModel>> getEventByJoinCode(String joinCode) async {
    await _delay();
    try {
      final event = _events.values.firstWhere(
        (e) => e.joinCode?.toUpperCase() == joinCode.toUpperCase(),
      );
      return Ok(event);
    } catch (_) {
      return const Err(NetworkFailure(
        message: 'No active event found for this code. Please check and try again.',
        statusCode: 404,
      ));
    }
  }

  @override
  Future<Result<EventModel>> createEvent(EventModel event) async {
    await _delay();
    _events[event.id] = event;
    _parties[event.id] = [];
    return Ok(event);
  }

  @override
  Future<Result<Unit>> updateEvent(EventModel event) async {
    await _delay();
    if (!_events.containsKey(event.id)) {
      return const Err(NetworkFailure(
        message: 'Event not found. It may have been deleted.',
        statusCode: 404,
      ));
    }
    _events[event.id] = event;
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<Unit>> deactivateEvent(String eventId) async {
    await _delay();
    final event = _events[eventId];
    if (event == null) {
      return const Err(NetworkFailure(
        message: 'Event not found.',
        statusCode: 404,
      ));
    }
    _events[eventId] = event.copyWith(isActive: false);
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<List<EventModel>>> getEventsByAdmin(String adminId) async {
    await _delay();
    final list = _events.values
        .where((e) => e.adminId == adminId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return Ok(list);
  }

  // ── Guest party operations ─────────────────────────────────────────────────

  @override
  Future<Result<EventGuestParty>> joinEvent(EventGuestParty party) async {
    await _delay(ms: 400);
    _parties.putIfAbsent(party.eventId, () => []).add(party);
    return Ok(party);
  }

  @override
  Future<Result<List<EventGuestParty>>> getPartiesForEvent(
      String eventId) async {
    await _delay();
    final parties = List<EventGuestParty>.unmodifiable(
      _parties[eventId] ?? const [],
    );
    return Ok(parties);
  }

  @override
  Future<Result<Unit>> updateGuestName({
    required String partyId,
    required String personId,
    required String newName,
  }) async {
    await _delay(ms: 200);
    final found = _updateParty(
        partyId, (party) => party.renamePerson(personId, newName));
    if (!found) {
      return const Err(NetworkFailure(
        message: 'Guest party not found.',
        statusCode: 404,
      ));
    }
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<Unit>> updateMealPreference({
    required String partyId,
    required String personId,
    required MealPreferenceOption preference,
  }) async {
    await _delay(ms: 200);
    final found = _updateParty(
      partyId,
      (party) => party.setMealPreference(personId, preference),
    );
    if (!found) {
      return const Err(NetworkFailure(
        message: 'Guest party not found.',
        statusCode: 404,
      ));
    }
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<Unit>> updateEventMealTypeId({
    required String partyId,
    required String personId,
    required String? mealTypeId,
  }) async {
    await _delay(ms: 200);
    final found = _updateParty(
      partyId,
      (party) => party.setEventMealTypeId(personId, mealTypeId),
    );
    if (!found) {
      return const Err(NetworkFailure(
        message: 'Guest party not found.',
        statusCode: 404,
      ));
    }
    return const Ok(Unit.instance);
  }

  @override
  Future<Result<Unit>> removeParty(String partyId) async {
    await _delay(ms: 300);
    for (final key in _parties.keys) {
      final before = _parties[key]!.length;
      _parties[key]!.removeWhere((p) => p.id == partyId);
      if (_parties[key]!.length < before) return const Ok(Unit.instance);
    }
    return const Err(NetworkFailure(
      message: 'Guest party not found.',
      statusCode: 404,
    ));
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  @override
  Future<Result<Map<String, int>>> getAttendanceSummary(
      String eventId) async {
    await _delay();
    final parties = _parties[eventId] ?? [];
    final allPersons = parties.expand((p) => p.persons).toList();
    return Ok({
      'total': allPersons.length,
      'adults': allPersons.where((p) => p.isAdult).length,
      'children': allPersons.where((p) => !p.isAdult).length,
      'pending':
          allPersons.where((p) => p.selectedMealTypeId == null).length,
    });
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _delay({int ms = 300}) =>
      Future.delayed(Duration(milliseconds: ms));

  bool _updateParty(
    String partyId,
    EventGuestParty Function(EventGuestParty) updater,
  ) {
    for (final key in _parties.keys) {
      final idx = _parties[key]!.indexWhere((p) => p.id == partyId);
      if (idx != -1) {
        _parties[key]![idx] = updater(_parties[key]![idx]);
        return true;
      }
    }
    return false;
  }
}

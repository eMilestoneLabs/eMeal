import 'package:smart_meal_management/core/errors/failure.dart';
import 'package:smart_meal_management/data/contracts/i_event_repository.dart';
import 'package:smart_meal_management/data/services/dio_api_service.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart'
    show MealPreferenceOption;
import 'package:smart_meal_management/shared/models/result.dart';

// ── EventRepository ───────────────────────────────────────────────────────────

/// Event repository — calls the live NestJS backend through [DioApiService].
///
/// The IEventRepository contract addresses persons by partyId, but backend
/// routes are `/events/:eventId/...` — the internal indices below bridge the
/// two without changing the locked contract; they are populated by every read
/// that sees the data.
class EventRepository implements IEventRepository {
  static final Map<String, String> _joinCodeByEventId = {};
  static final Map<String, String> _eventIdByPartyId = {};

  void _indexEvent(EventModel e) {
    if (e.joinCode != null && e.joinCode!.isNotEmpty) {
      _joinCodeByEventId[e.id] = e.joinCode!;
    }
  }

  void _indexParty(EventGuestParty p) {
    if (p.id.isNotEmpty && p.eventId.isNotEmpty) {
      _eventIdByPartyId[p.id] = p.eventId;
    }
  }

  static const _kPartyNotIndexed = NetworkFailure(
    message: 'Guest party not loaded yet. Pull to refresh and try again.',
  );

  // ── Event CRUD ─────────────────────────────────────────────────────────────

  @override
  Future<Result<EventModel>> getEvent(String eventId) async {
    final result =
        await DioApiService.instance.get<Map<String, dynamic>>('/events/$eventId');
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final event = EventModel.fromJson(value);
        _indexEvent(event);
        return Ok(event);
    }
  }

  @override
  Future<Result<EventModel>> getEventByJoinCode(String joinCode) async {
    // Public QR-resolve endpoint — no JWT required for event guests.
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/events/join/${joinCode.trim()}',
      requiresAuth: false,
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final event = EventModel.fromJson(value);
        _indexEvent(event);
        if (event.joinCode == null || event.joinCode!.isEmpty) {
          // Guarantee the join flow can POST /events/join later.
          _joinCodeByEventId[event.id] = joinCode.trim();
        }
        return Ok(event);
    }
  }

  @override
  Future<Result<EventModel>> createEvent(EventModel event) async {
    // CreateEventDto whitelist: name, type, eventDate, expectedGuestCount,
    // autoDeleteAfter7Days. NEVER send the full toJson() — the backend
    // ValidationPipe (forbidNonWhitelisted) rejects unknown keys with 422.
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/events',
      body: {
        'name': event.name,
        'type': event.type.name,
        'eventDate': event.date.toUtc().toIso8601String(),
        'expectedGuestCount': event.expectedGuestCount,
        'autoDeleteAfter7Days': event.autoDeleteAfter7Days,
      },
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final created = EventModel.fromJson(value);
        _indexEvent(created);
        return Ok(created);
    }
  }

  @override
  Future<Result<Unit>> updateEvent(EventModel event) async {
    // 1. PATCH the scalar fields (UpdateEventDto whitelist).
    final patchResult = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/events/${event.id}',
      body: {
        'name': event.name,
        'type': event.type.name,
        'eventDate': event.date.toUtc().toIso8601String(),
        'expectedGuestCount': event.expectedGuestCount,
        'autoDeleteAfter7Days': event.autoDeleteAfter7Days,
        'isActive': event.isActive,
      },
    );
    if (patchResult case Err(:final failure)) return Err(failure);

    // 2. Sync meal types — the locked contract edits them through updateEvent,
    //    but the backend manages them via /events/:id/meal-types. Diff against
    //    the server state and create / update / delete accordingly.
    final serverResult =
        await DioApiService.instance.get<Map<String, dynamic>>('/events/${event.id}');
    if (serverResult case Err(:final failure)) return Err(failure);
    final server = EventModel.fromJson((serverResult as Ok<Map<String, dynamic>>).value);
    _indexEvent(server);

    final serverById = {for (final mt in server.mealTypes) mt.id: mt};
    final localIds = event.mealTypes.map((mt) => mt.id).toSet();

    for (final mt in event.mealTypes) {
      final existing = serverById[mt.id];
      if (existing == null) {
        // New (locally-generated id) → create on the server.
        final res = await DioApiService.instance.post<Map<String, dynamic>>(
          '/events/${event.id}/meal-types',
          body: {
            'title': mt.title,
            'emoji': mt.emoji,
            'colorValue': mt.color.toARGB32(),
            'isVeg': mt.isVeg,
          },
        );
        if (res case Err(:final failure)) return Err(failure);
      } else if (existing.title != mt.title ||
          existing.emoji != mt.emoji ||
          existing.isVeg != mt.isVeg ||
          existing.color.toARGB32() != mt.color.toARGB32()) {
        final res = await DioApiService.instance.patch<Map<String, dynamic>>(
          '/events/${event.id}/meal-types/${mt.id}',
          body: {
            'title': mt.title,
            'emoji': mt.emoji,
            'colorValue': mt.color.toARGB32(),
            'isVeg': mt.isVeg,
          },
        );
        if (res case Err(:final failure)) return Err(failure);
      }
    }

    for (final mt in server.mealTypes) {
      if (!localIds.contains(mt.id)) {
        // Removed locally → delete. Backend returns 409 when guests already
        // selected it (GAP-EVT-2) — surfaced to the provider as a failure.
        final res = await DioApiService.instance
            .delete<dynamic>('/events/${event.id}/meal-types/${mt.id}');
        if (res case Err(:final failure)) return Err(failure);
      }
    }

    return const Ok(Unit.instance);
  }

  @override
  Future<Result<Unit>> deactivateEvent(String eventId) async {
    final result =
        await DioApiService.instance.delete<dynamic>('/events/$eventId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  @override
  Future<Result<List<EventModel>>> getEventsByAdmin(String adminId) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/events',
      queryParameters: {'page': '1', 'limit': '100'},
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final items = (value['data'] as List<dynamic>? ?? [])
            .map((j) => EventModel.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
        for (final e in items) {
          _indexEvent(e);
        }
        // Org-scoped on the server; admin-scoped here (event admins own their
        // org, so this is a display filter — not a security boundary).
        final mine = items.where((e) => e.adminId == adminId || adminId.isEmpty).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return Ok(mine.isEmpty ? items : mine);
    }
  }

  // ── Guest party operations ─────────────────────────────────────────────────

  @override
  Future<Result<EventGuestParty>> joinEvent(EventGuestParty party) async {
    // Guests are unauthenticated — the ONLY public join route is
    // POST /events/join { joinCode, primaryName, adultsCount, childrenCount }.
    // The guest flow always resolves the event via getEventByJoinCode first,
    // which populates _joinCodeByEventId.
    final joinCode = _joinCodeByEventId[party.eventId];
    if (joinCode == null) {
      return const Err(NetworkFailure(
        message: 'Event join code not available. Scan the QR code again.',
      ));
    }
    final result = await DioApiService.instance.post<Map<String, dynamic>>(
      '/events/join',
      body: {
        'joinCode': joinCode,
        'primaryName': party.primaryName,
        'adultsCount': party.adultsCount,
        'childrenCount': party.childrenCount,
      },
      requiresAuth: false,
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final created = EventGuestParty.fromJson(value);
        final withEvent = created.eventId.isEmpty
            ? EventGuestParty(
                id: created.id,
                eventId: party.eventId,
                primaryName: created.primaryName,
                adultsCount: created.adultsCount,
                childrenCount: created.childrenCount,
                persons: created.persons,
                joinedAt: created.joinedAt,
              )
            : created;
        _indexParty(withEvent);
        return Ok(withEvent);
    }
  }

  @override
  Future<Result<List<EventGuestParty>>> getPartiesForEvent(String eventId) async {
    final result = await DioApiService.instance.get<Map<String, dynamic>>(
      '/events/$eventId/parties',
      queryParameters: {'page': '1', 'limit': '200'},
    );
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        final parties = (value['data'] as List<dynamic>? ?? [])
            .map((j) =>
                EventGuestParty.fromJson(Map<String, dynamic>.from(j as Map)))
            .toList();
        for (final p in parties) {
          _indexParty(p);
          if (p.eventId.isEmpty) _eventIdByPartyId[p.id] = eventId;
        }
        return Ok(parties);
    }
  }

  @override
  Future<Result<Unit>> updateGuestName({
    required String partyId,
    required String personId,
    required String newName,
  }) async {
    return _patchPerson(partyId, personId, {'displayName': newName});
  }

  @override
  Future<Result<Unit>> updateMealPreference({
    required String partyId,
    required String personId,
    required MealPreferenceOption preference,
  }) async {
    return _patchPerson(partyId, personId, {'mealPreference': preference.name});
  }

  @override
  Future<Result<Unit>> updateEventMealTypeId({
    required String partyId,
    required String personId,
    required String? mealTypeId,
  }) async {
    return _patchPerson(
        partyId, personId, {'selectedMealTypeId': mealTypeId});
  }

  Future<Result<Unit>> _patchPerson(
    String partyId,
    String personId,
    Map<String, dynamic> body,
  ) async {
    final eventId = _eventIdByPartyId[partyId];
    if (eventId == null) return const Err(_kPartyNotIndexed);
    final result = await DioApiService.instance.patch<Map<String, dynamic>>(
      '/events/$eventId/persons/$personId',
      body: body,
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  @override
  Future<Result<Unit>> removeParty(String partyId) async {
    final eventId = _eventIdByPartyId[partyId];
    if (eventId == null) return const Err(_kPartyNotIndexed);
    final result = await DioApiService.instance
        .delete<dynamic>('/events/$eventId/parties/$partyId');
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok() => const Ok(Unit.instance),
    };
  }

  // ── Analytics ─────────────────────────────────────────────────────────────

  @override
  Future<Result<Map<String, int>>> getAttendanceSummary(String eventId) async {
    // GET /events/:id/stats — M-18 contract:
    // { total, adults, children, present, pending, vegCount, nonVegCount, mealTypeBreakdown }
    final result = await DioApiService.instance
        .get<Map<String, dynamic>>('/events/$eventId/stats');
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        int asInt(dynamic v) => (v as num?)?.toInt() ?? 0;
        return Ok({
          'total': asInt(value['total']),
          'adults': asInt(value['adults']),
          'children': asInt(value['children']),
          'present': asInt(value['present']),
          'pending': asInt(value['pending']),
          'vegCount': asInt(value['vegCount']),
          'nonVegCount': asInt(value['nonVegCount']),
        });
    }
  }
}

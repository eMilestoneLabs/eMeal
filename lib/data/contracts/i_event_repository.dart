import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/features/events/models/event_model.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';
import 'package:smart_meal_management/shared/models/result.dart';

// ── IEventRepository ───────────────────────────────────────────────────────────

/// Contract for all event data operations.
///
/// All methods return [Result<T>] — consistent with every other repository
/// contract in the project. Implementations must never throw; they wrap errors
/// in [Err] with an appropriate [Failure] subtype.
///
/// Implemented by [EventRepository] against the live NestJS REST backend.
abstract interface class IEventRepository {
  // ── Event CRUD ────────────────────────────────────────────────────────────

  Future<Result<EventModel>> getEvent(String eventId);

  Future<Result<EventModel>> getEventByJoinCode(String joinCode);

  Future<Result<EventModel>> createEvent(EventModel event);

  Future<Result<Unit>> updateEvent(EventModel event);

  Future<Result<Unit>> deactivateEvent(String eventId);

  Future<Result<List<EventModel>>> getEventsByAdmin(String adminId);

  // ── Guest party operations ────────────────────────────────────────────────

  Future<Result<EventGuestParty>> joinEvent(EventGuestParty party);

  Future<Result<List<EventGuestParty>>> getPartiesForEvent(String eventId);

  Future<Result<Unit>> updateGuestName({
    required String partyId,
    required String personId,
    required String newName,
  });

  Future<Result<Unit>> updateMealPreference({
    required String partyId,
    required String personId,
    required MealPreferenceOption preference,
  });

  /// Updates a person's selected event meal type ID.
  Future<Result<Unit>> updateEventMealTypeId({
    required String partyId,
    required String personId,
    required String? mealTypeId,
  });

  Future<Result<Unit>> removeParty(String partyId);

  // ── Analytics ─────────────────────────────────────────────────────────────

  Future<Result<Map<String, int>>> getAttendanceSummary(String eventId);
}

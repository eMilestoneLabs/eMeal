import 'package:smart_meal_management/features/events/models/guest_person.dart';
import 'package:smart_meal_management/shared/models/group_model.dart';

// ── EventGuestParty ────────────────────────────────────────────────────────────

/// Represents a group of people that joined an event together under one
/// primary guest's identity.
///
/// The primary guest enters:
///   - Their own name (becomes [primaryName])
///   - [adultsCount] — total adults including themselves
///   - [childrenCount] — total children
///
/// [generatePersons] expands these counts into individual [GuestPerson] entries
/// so that each person can independently select their meal type and attendance.
///
/// ```
/// Rahul Mahanta (3 adults, 2 children) →
///   [0] Rahul Mahanta  — primary, adult, isPrimary=true
///   [1] Guest-2        — adult
///   [2] Guest-3        — adult
///   [3] Guest-4        — child
///   [4] Guest-5        — child
/// ```
class EventGuestParty {
  EventGuestParty({
    required this.id,
    required this.eventId,
    required this.primaryName,
    required this.adultsCount,
    required this.childrenCount,
    List<GuestPerson>? persons,
    this.joinedAt,
  }) : persons = persons ??
            _generatePersons(id, primaryName, adultsCount, childrenCount);

  final String id;
  final String eventId;

  /// Name entered by the person who scanned the QR / joined the event.
  final String primaryName;

  /// Total adults in this party (including the primary guest).
  final int adultsCount;

  final int childrenCount;

  /// Expanded list of individual [GuestPerson] entries.
  ///
  /// Length == [adultsCount] + [childrenCount].
  /// Index 0 is always the primary guest.
  final List<GuestPerson> persons;

  final DateTime? joinedAt;

  // ── Computed ──────────────────────────────────────────────────────────────

  int get totalCount => adultsCount + childrenCount;

  /// Veg count based on hostel [MealPreferenceOption].
  int get vegCount =>
      persons.where((p) => p.isVeg && p.isPresent).length;

  /// Non-veg count based on hostel [MealPreferenceOption].
  int get nonVegCount =>
      persons
          .where((p) =>
              !p.isVeg && p.mealPreference != null && p.isPresent)
          .length;

  int get presentCount => persons.where((p) => p.isPresent).length;
  int get absentCount => persons.where((p) => !p.isPresent).length;

  /// Count of persons who selected a specific event meal type.
  int eventMealCount(String mealTypeId) =>
      persons
          .where((p) => p.selectedMealTypeId == mealTypeId && p.isPresent)
          .length;

  /// Adult count selecting a specific event meal type.
  int eventMealAdultCount(String mealTypeId) =>
      persons
          .where((p) =>
              p.selectedMealTypeId == mealTypeId &&
              p.isPresent &&
              p.isAdult)
          .length;

  /// Child count selecting a specific event meal type.
  int eventMealChildCount(String mealTypeId) =>
      persons
          .where((p) =>
              p.selectedMealTypeId == mealTypeId &&
              p.isPresent &&
              !p.isAdult)
          .length;

  /// Returns true when every present person has chosen an event meal type.
  bool get allEventMealsSelected =>
      persons.where((p) => p.isPresent).every((p) => p.selectedMealTypeId != null);

  /// Returns true when every present person has chosen a hostel meal preference.
  bool get allPreferencesSelected =>
      persons.where((p) => p.isPresent).every((p) => p.mealPreference != null);

  // ── Static generator ──────────────────────────────────────────────────────

  static List<GuestPerson> _generatePersons(
    String partyId,
    String primaryName,
    int adultsCount,
    int childrenCount,
  ) {
    final persons = <GuestPerson>[];
    var guestIndex = 1;

    // Adults first — primary guest is index 0.
    for (var i = 0; i < adultsCount; i++) {
      final isPrimary = i == 0;
      persons.add(GuestPerson(
        id: '${partyId}_p$guestIndex',
        displayName: isPrimary ? primaryName : 'Guest-$guestIndex',
        isAdult: true,
        isPrimary: isPrimary,
      ));
      guestIndex++;
    }

    // Children.
    for (var i = 0; i < childrenCount; i++) {
      persons.add(GuestPerson(
        id: '${partyId}_p$guestIndex',
        displayName: 'Guest-$guestIndex',
        isAdult: false,
      ));
      guestIndex++;
    }

    return persons;
  }

  // ── Person mutation helpers ───────────────────────────────────────────────

  /// Returns a new [EventGuestParty] with [person] updated by [updater].
  EventGuestParty updatePerson(
    String personId,
    GuestPerson Function(GuestPerson) updater,
  ) {
    final updated =
        persons.map((p) => p.id == personId ? updater(p) : p).toList();
    return _copyWithPersons(updated);
  }

  /// Renames a non-primary guest.
  EventGuestParty renamePerson(String personId, String newName) {
    return updatePerson(
      personId,
      (p) => p.copyWith(displayName: newName, isNameEdited: true),
    );
  }

  /// Sets the hostel meal preference for a specific person.
  EventGuestParty setMealPreference(
      String personId, MealPreferenceOption pref) {
    return updatePerson(personId, (p) => p.copyWith(mealPreference: pref));
  }

  /// Sets the event meal type id for a specific person.
  EventGuestParty setEventMealTypeId(String personId, String? mealTypeId) {
    return updatePerson(
      personId,
      (p) => mealTypeId == null
          ? p.copyWith(clearMealTypeId: true)
          : p.copyWith(selectedMealTypeId: mealTypeId),
    );
  }

  /// Toggles attendance for a specific person.
  EventGuestParty toggleAttendance(String personId) {
    return updatePerson(personId, (p) => p.copyWith(isPresent: !p.isPresent));
  }

  EventGuestParty _copyWithPersons(List<GuestPerson> newPersons) =>
      EventGuestParty(
        id: id,
        eventId: eventId,
        primaryName: primaryName,
        adultsCount: adultsCount,
        childrenCount: childrenCount,
        persons: newPersons,
        joinedAt: joinedAt,
      );

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory EventGuestParty.fromJson(Map<String, dynamic> j) {
    final personsJson = j['persons'] as List<dynamic>? ?? [];
    return EventGuestParty(
      id: j['id'] ?? '',
      eventId: j['eventId'] ?? '',
      primaryName: j['primaryName'] ?? '',
      adultsCount: j['adultsCount'] ?? 1,
      childrenCount: j['childrenCount'] ?? 0,
      persons: personsJson
          .map((p) =>
              GuestPerson.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      joinedAt:
          j['joinedAt'] != null ? DateTime.parse(j['joinedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventId': eventId,
        'primaryName': primaryName,
        'adultsCount': adultsCount,
        'childrenCount': childrenCount,
        'persons': persons.map((p) => p.toJson()).toList(),
        'joinedAt': joinedAt?.toIso8601String(),
      };
}

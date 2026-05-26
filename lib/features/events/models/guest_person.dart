import 'package:smart_meal_management/shared/models/group_model.dart';

// ── GuestPerson ────────────────────────────────────────────────────────────────

/// Represents a single person within an [EventGuestParty].
///
/// The primary guest (index 0) uses the name they entered during join.
/// All subsequent guests default to "Guest-N" but can be renamed inline by
/// the primary guest from the event guest dashboard.
///
/// Two meal-selection fields exist:
///   - [mealPreference]    — used by the hostel/mess system (MealPreferenceOption enum)
///   - [selectedMealTypeId] — used by the event system (dynamic EventMealType id)
///
/// Only one is populated at a time depending on context.
class GuestPerson {
  GuestPerson({
    required this.id,
    required this.displayName,
    required this.isAdult,
    this.mealPreference,
    this.selectedMealTypeId,
    this.isNameEdited = false,
    this.isPrimary = false,
    this.isPresent = true,
  });

  /// Unique identifier within the party. Format: `{partyId}_p{index}`.
  final String id;

  /// Editable display name. Defaults to "Guest-N" for non-primary members.
  String displayName;

  /// True for adult guests, false for children.
  final bool isAdult;

  /// Hostel/mess system meal preference.
  ///
  /// Null means not yet selected.
  MealPreferenceOption? mealPreference;

  /// Event system meal type ID — references an [EventMealType.id].
  ///
  /// Null means guest has not yet selected their meal for the event.
  String? selectedMealTypeId;

  /// True once the primary guest has manually set a name for this person.
  bool isNameEdited;

  /// True only for the first person in the party (the guest who joined).
  final bool isPrimary;

  /// Whether this person is attending (present). Defaults to true.
  final bool isPresent;

  // ── Derived ───────────────────────────────────────────────────────────────

  /// Vegetarian check based on hostel meal preference.
  bool get isVeg => mealPreference?.isVegetarian ?? false;

  /// Label used on the guest list tag (e.g. "Adult" / "Child").
  String get ageLabel => isAdult ? 'Adult' : 'Child';

  /// True when an event meal type has been chosen.
  bool get hasEventMeal => selectedMealTypeId != null;

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory GuestPerson.fromJson(Map<String, dynamic> j) => GuestPerson(
        id: j['id'] ?? '',
        displayName: j['displayName'] ?? 'Guest',
        isAdult: j['isAdult'] ?? true,
        mealPreference: j['mealPreference'] != null
            ? MealPreferenceOption.values.firstWhere(
                (p) => p.name == j['mealPreference'],
                orElse: () => MealPreferenceOption.veg,
              )
            : null,
        selectedMealTypeId: j['selectedMealTypeId'] as String?,
        isNameEdited: j['isNameEdited'] ?? false,
        isPrimary: j['isPrimary'] ?? false,
        isPresent: j['isPresent'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'isAdult': isAdult,
        'mealPreference': mealPreference?.name,
        'selectedMealTypeId': selectedMealTypeId,
        'isNameEdited': isNameEdited,
        'isPrimary': isPrimary,
        'isPresent': isPresent,
      };

  GuestPerson copyWith({
    String? displayName,
    MealPreferenceOption? mealPreference,
    String? selectedMealTypeId,
    bool? clearMealTypeId,
    bool? isNameEdited,
    bool? isPresent,
  }) =>
      GuestPerson(
        id: id,
        displayName: displayName ?? this.displayName,
        isAdult: isAdult,
        mealPreference: mealPreference ?? this.mealPreference,
        selectedMealTypeId: (clearMealTypeId == true)
            ? null
            : (selectedMealTypeId ?? this.selectedMealTypeId),
        isNameEdited: isNameEdited ?? this.isNameEdited,
        isPrimary: isPrimary,
        isPresent: isPresent ?? this.isPresent,
      );

  @override
  String toString() =>
      'GuestPerson($id, $displayName, ${isAdult ? "adult" : "child"})';
}

import 'package:equatable/equatable.dart';
import 'package:smart_meal_management/features/events/models/event_meal_type.dart';

// ── EventType ──────────────────────────────────────────────────────────────────

/// The occasion/category of an event.
enum EventType {
  wedding,
  corporate,
  birthday,
  festival,
  conference,
  other;

  String get label {
    switch (this) {
      case EventType.wedding:
        return 'Wedding';
      case EventType.corporate:
        return 'Corporate Event';
      case EventType.birthday:
        return 'Birthday';
      case EventType.festival:
        return 'Festival';
      case EventType.conference:
        return 'Conference';
      case EventType.other:
        return 'Other';
    }
  }

  String get emoji {
    switch (this) {
      case EventType.wedding:
        return '💍';
      case EventType.corporate:
        return '🏢';
      case EventType.birthday:
        return '🎂';
      case EventType.festival:
        return '🎉';
      case EventType.conference:
        return '🎤';
      case EventType.other:
        return '📅';
    }
  }
}

// ── EventStatus ────────────────────────────────────────────────────────────────

enum EventStatus {
  upcoming,
  active,
  ended,
  expired;

  String get label {
    switch (this) {
      case EventStatus.upcoming:
        return 'Upcoming';
      case EventStatus.active:
        return 'Active';
      case EventStatus.ended:
        return 'Ended';
      case EventStatus.expired:
        return 'Expired';
    }
  }
}

// ── EventModel ─────────────────────────────────────────────────────────────────

/// Represents a single event created by an [eventAdmin].
///
/// Meal configuration is now fully dynamic via [mealTypes] — admins create
/// custom [EventMealType] entries (e.g. "Chicken", "Dessert", "Jain") instead
/// of toggling fixed boolean flags.
class EventModel extends Equatable {
  const EventModel({
    required this.id,
    required this.name,
    required this.type,
    required this.date,
    required this.expectedGuestCount,
    required this.adminId,
    required this.adminName,
    this.mealTypes = const [],
    this.autoDeleteAfter7Days = true,
    this.isActive = true,
    this.createdAt,
    this.joinCode,
  });

  final String id;
  final String name;
  final EventType type;

  /// The date of the event (time component ignored — date only matters).
  final DateTime date;

  final int expectedGuestCount;
  final String adminId;
  final String adminName;

  /// Admin-created dynamic meal types for this event.
  ///
  /// Guests select one of these when joining. Empty = no meal config yet.
  final List<EventMealType> mealTypes;

  final bool autoDeleteAfter7Days;
  final bool isActive;
  final DateTime? createdAt;

  /// 6-character alphanumeric code guests can enter instead of scanning a QR.
  final String? joinCode;

  // ── Computed ─────────────────────────────────────────────────────────────────

  EventStatus get status {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);

    if (!isActive) return EventStatus.expired;
    if (autoDeleteAfter7Days &&
        now.isAfter(date.add(const Duration(days: 7)))) {
      return EventStatus.expired;
    }
    if (today.isAtSameMomentAs(eventDay)) return EventStatus.active;
    if (today.isBefore(eventDay)) return EventStatus.upcoming;
    return EventStatus.ended;
  }

  bool get isExpired => status == EventStatus.expired;
  bool get hasMealTypes => mealTypes.isNotEmpty;

  String get formattedDate {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  // ── Serialisation ─────────────────────────────────────────────────────────────

  factory EventModel.fromJson(Map<String, dynamic> j) => EventModel(
        id: j['id'] ?? '',
        name: j['name'] ?? 'Event',
        type: EventType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => EventType.other,
        ),
        date: j['date'] != null ? DateTime.parse(j['date']) : DateTime.now(),
        expectedGuestCount: j['expectedGuestCount'] ?? 0,
        adminId: j['adminId'] ?? '',
        adminName: j['adminName'] ?? '',
        mealTypes: (j['mealTypes'] as List<dynamic>? ?? [])
            .map((m) =>
                EventMealType.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList(),
        autoDeleteAfter7Days: j['autoDeleteAfter7Days'] ?? true,
        isActive: j['isActive'] ?? true,
        createdAt:
            j['createdAt'] != null ? DateTime.parse(j['createdAt']) : null,
        joinCode: j['joinCode'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'date': date.toIso8601String(),
        'expectedGuestCount': expectedGuestCount,
        'adminId': adminId,
        'adminName': adminName,
        'mealTypes': mealTypes.map((m) => m.toJson()).toList(),
        'autoDeleteAfter7Days': autoDeleteAfter7Days,
        'isActive': isActive,
        'createdAt': createdAt?.toIso8601String(),
        'joinCode': joinCode,
      };

  EventModel copyWith({
    String? name,
    EventType? type,
    DateTime? date,
    int? expectedGuestCount,
    List<EventMealType>? mealTypes,
    bool? autoDeleteAfter7Days,
    bool? isActive,
    String? joinCode,
  }) =>
      EventModel(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        date: date ?? this.date,
        expectedGuestCount: expectedGuestCount ?? this.expectedGuestCount,
        adminId: adminId,
        adminName: adminName,
        mealTypes: mealTypes ?? this.mealTypes,
        autoDeleteAfter7Days: autoDeleteAfter7Days ?? this.autoDeleteAfter7Days,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        joinCode: joinCode ?? this.joinCode,
      );

  @override
  List<Object?> get props => [id, name, type, date, isActive, mealTypes];
}

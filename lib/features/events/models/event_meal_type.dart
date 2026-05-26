import 'package:flutter/material.dart';

// ── EventMealType ──────────────────────────────────────────────────────────────

/// A single dynamically-created meal type for an event.
///
/// Event admins create these from scratch — they are NOT the same as the
/// hostel-system [MealPreferenceOption] enum. Each type has:
///   - a human-readable [title]  (e.g. "Chicken", "Dessert", "Jain")
///   - an [emoji]  displayed on tiles and chips
///   - a [color]  used for card borders and stat chips
///   - [isVeg] flag for veg/non-veg analytics
///
/// IDs are generated at creation time and stable for the event's lifetime.
class EventMealType {
  const EventMealType({
    required this.id,
    required this.title,
    required this.emoji,
    required this.color,
    this.isVeg = false,
  });

  final String id;
  final String title;
  final String emoji;

  /// Display color for chips, borders, and stat indicators.
  final Color color;

  /// True for vegetarian options (used in veg/non-veg aggregate counts).
  final bool isVeg;

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory EventMealType.fromJson(Map<String, dynamic> j) => EventMealType(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '🍽',
        color: Color(j['colorValue'] as int? ?? 0xFF9E9E9E),
        isVeg: j['isVeg'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'emoji': emoji,
        'colorValue': color.toARGB32(),
        'isVeg': isVeg,
      };

  EventMealType copyWith({
    String? title,
    String? emoji,
    Color? color,
    bool? isVeg,
  }) =>
      EventMealType(
        id: id,
        title: title ?? this.title,
        emoji: emoji ?? this.emoji,
        color: color ?? this.color,
        isVeg: isVeg ?? this.isVeg,
      );

  // ── Quick-add presets ─────────────────────────────────────────────────────

  /// Preset options shown in the "Add Meal Type" picker so admins can
  /// tap-to-add common types instead of typing from scratch.
  static const List<EventMealType> presets = [
    EventMealType(
        id: '_preset_veg',
        title: 'Veg',
        emoji: '🥗',
        color: Color(0xFF4CAF50),
        isVeg: true),
    EventMealType(
        id: '_preset_jain',
        title: 'Jain',
        emoji: '🙏',
        color: Color(0xFF8BC34A),
        isVeg: true),
    EventMealType(
        id: '_preset_egg',
        title: 'Egg',
        emoji: '🥚',
        color: Color(0xFFFFC107),
        isVeg: true),
    EventMealType(
        id: '_preset_chicken',
        title: 'Chicken',
        emoji: '🍗',
        color: Color(0xFFFF5722),
        isVeg: false),
    EventMealType(
        id: '_preset_fish',
        title: 'Fish',
        emoji: '🐟',
        color: Color(0xFF2196F3),
        isVeg: false),
    EventMealType(
        id: '_preset_mutton',
        title: 'Mutton',
        emoji: '🍖',
        color: Color(0xFF9C27B0),
        isVeg: false),
    EventMealType(
        id: '_preset_dessert',
        title: 'Dessert',
        emoji: '🎂',
        color: Color(0xFFE91E63),
        isVeg: true),
    EventMealType(
        id: '_preset_drinks',
        title: 'Drinks',
        emoji: '🥤',
        color: Color(0xFF00BCD4),
        isVeg: true),
  ];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is EventMealType && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'EventMealType($id, $title)';
}

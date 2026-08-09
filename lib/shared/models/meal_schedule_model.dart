import 'dart:convert';

import 'package:flutter/foundation.dart';

enum DayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday;

  String get label {
    switch (this) {
      case DayOfWeek.monday:
        return 'Mon';
      case DayOfWeek.tuesday:
        return 'Tue';
      case DayOfWeek.wednesday:
        return 'Wed';
      case DayOfWeek.thursday:
        return 'Thu';
      case DayOfWeek.friday:
        return 'Fri';
      case DayOfWeek.saturday:
        return 'Sat';
      case DayOfWeek.sunday:
        return 'Sun';
    }
  }

  String get fullLabel {
    switch (this) {
      case DayOfWeek.monday:
        return 'Monday';
      case DayOfWeek.tuesday:
        return 'Tuesday';
      case DayOfWeek.wednesday:
        return 'Wednesday';
      case DayOfWeek.thursday:
        return 'Thursday';
      case DayOfWeek.friday:
        return 'Friday';
      case DayOfWeek.saturday:
        return 'Saturday';
      case DayOfWeek.sunday:
        return 'Sunday';
    }
  }

  /// 3-letter abbreviated label (alias for [label]).
  String get shortLabel => label;

  /// Convert from Dart's DateTime.weekday (1=Mon … 7=Sun)
  static DayOfWeek fromWeekday(int weekday) =>
      DayOfWeek.values[(weekday - 1) % 7];
}

/// A single meal entry within a day's schedule.
///
/// Each [DayMealEntry] is INDEPENDENT of every other day's entry for the
/// same meal — editing Monday's Breakfast does NOT affect Saturday's.
///
/// [openTime] / [closeTime] are optional per-day overrides.  When null the
/// consumer should fall back to the parent [MealModel]'s attendance window.
@immutable
class DayMealEntry {
  const DayMealEntry({
    required this.mealId,
    required this.name,
    required this.slotKey,
    required this.order,
    this.menuItems = const [],
    this.imageUrl,
    this.description,
    this.imageBytes = const [],
    this.openTime,
    this.closeTime,
    this.preferencesEnabled = false,
    this.enabledPreferences = const [],
    this.enabledPreferenceGroupIds = const [],
    this.price,
  });

  final String mealId;
  final String name;
  final String slotKey;
  final int order;
  final List<String> menuItems;
  final String? imageUrl;

  /// Per-day meal description override. Null = inherit the master meal's
  /// description. Persisted via the schedule entry (additive backend field).
  final String? description;

  /// Session-local compressed image bytes for this day's meal (max 1, ≤100 KB),
  /// mirroring the master meal editor. Not serialized — image persistence is
  /// handled by the shared (B11) upload path, identical to master meals.
  final List<Uint8List> imageBytes;

  /// Per-day attendance window open time (e.g. "07:30").
  /// Null means use the parent [MealModel] template window.
  final String? openTime;

  /// Per-day attendance window close time (e.g. "09:00").
  /// Null means use the parent [MealModel] template window.
  final String? closeTime;

  /// Per-day meal preference (#6) — independent from every other day.
  final bool preferencesEnabled;
  final List<String> enabledPreferences;

  /// #3: per-day SUBSET of the meal's master preference group ids that apply
  /// this day. Empty = inherit ALL master groups (unchanged behaviour).
  final List<String> enabledPreferenceGroupIds;

  /// Additive: per-day ₹ price override. Null = inherit master meal price.
  final int? price;

  /// True when this entry carries its own time window (overrides template).
  bool get hasCustomTiming => openTime != null && closeTime != null;

  /// Single image bytes to display: local session bytes first, otherwise the
  /// base64 JPEG data URI carried in [imageUrl] (how photos round-trip through
  /// the backend). Null when there's no photo or [imageUrl] is a network URL.
  Uint8List? get displayImageBytes {
    if (imageBytes.isNotEmpty) return imageBytes.first;
    final u = imageUrl;
    if (u != null && u.startsWith('data:image')) {
      final comma = u.indexOf(',');
      if (comma != -1) {
        try {
          return base64Decode(u.substring(comma + 1));
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  /// The plain network URL for this entry's photo, when [imageUrl] is an http(s)
  /// link (MinIO/CDN) rather than a base64 data URI. Null otherwise. Pairs with
  /// [displayImageBytes] (local/base64) — network image widgets render this.
  String? get networkImageUrl {
    final u = imageUrl;
    if (u != null && (u.startsWith('http://') || u.startsWith('https://'))) {
      return u;
    }
    return null;
  }

  /// True when this entry has a photo from any source (local/base64 or network).
  bool get hasDisplayImage =>
      displayImageBytes != null || networkImageUrl != null;

  factory DayMealEntry.fromJson(Map<String, dynamic> j) => DayMealEntry(
        mealId: j['mealId'] ?? '',
        name: j['name'] ?? '',
        slotKey: j['slotKey'] ?? 'meal',
        order: j['order'] ?? 0,
        menuItems: List<String>.from(j['menuItems'] ?? []),
        imageUrl: j['imageUrl'],
        description: j['description'] as String?,
        openTime: j['openTime'] as String?,
        closeTime: j['closeTime'] as String?,
        preferencesEnabled: j['preferencesEnabled'] ?? false,
        enabledPreferences: List<String>.from(j['enabledPreferences'] ?? []),
        enabledPreferenceGroupIds:
            List<String>.from(j['enabledPreferenceGroupIds'] ?? []),
        price: j['price'] is int
            ? j['price'] as int
            : (j['price'] != null
                ? int.tryParse(j['price'].toString())
                : null),
      );

  Map<String, dynamic> toJson() => {
        'mealId': mealId,
        'name': name,
        'slotKey': slotKey,
        'order': order,
        'menuItems': menuItems,
        'imageUrl': imageUrl,
        if (description != null) 'description': description,
        if (openTime != null) 'openTime': openTime,
        if (closeTime != null) 'closeTime': closeTime,
        'preferencesEnabled': preferencesEnabled,
        'enabledPreferences': enabledPreferences,
        'enabledPreferenceGroupIds': enabledPreferenceGroupIds,
        if (price != null) 'price': price,
      };

  DayMealEntry copyWith({
    String? name,
    List<String>? menuItems,
    String? imageUrl,
    String? description,
    List<Uint8List>? imageBytes,
    String? openTime,
    String? closeTime,
    bool? preferencesEnabled,
    List<String>? enabledPreferences,
    List<String>? enabledPreferenceGroupIds,
    int? price,
  }) =>
      DayMealEntry(
        mealId: mealId,
        name: name ?? this.name,
        slotKey: slotKey,
        order: order,
        menuItems: menuItems ?? this.menuItems,
        imageUrl: imageUrl ?? this.imageUrl,
        description: description ?? this.description,
        imageBytes: imageBytes ?? this.imageBytes,
        openTime: openTime ?? this.openTime,
        closeTime: closeTime ?? this.closeTime,
        preferencesEnabled: preferencesEnabled ?? this.preferencesEnabled,
        enabledPreferences: enabledPreferences ?? this.enabledPreferences,
        enabledPreferenceGroupIds:
            enabledPreferenceGroupIds ?? this.enabledPreferenceGroupIds,
        price: price ?? this.price,
      );
}

/// Full schedule for one day.
@immutable
class DaySchedule {
  const DaySchedule({required this.day, required this.meals});
  final DayOfWeek day;
  final List<DayMealEntry> meals;

  factory DaySchedule.fromJson(Map<String, dynamic> j) => DaySchedule(
        day: DayOfWeek.values.firstWhere(
          (d) => d.name == j['day'],
          orElse: () => DayOfWeek.monday,
        ),
        meals: (j['meals'] as List? ?? [])
            .map((m) => DayMealEntry.fromJson(m))
            .toList(),
      );

  bool get isEmpty => meals.isEmpty;
  bool get isNotEmpty => meals.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'day': day.name,
        'meals': meals.map((m) => m.toJson()).toList(),
      };
}

/// Full weekly schedule model returned by the repository.
@immutable
class MealScheduleModel {
  const MealScheduleModel({
    required this.id,
    required this.groupId,
    required this.organizationId,
    required this.days,
    this.isPublished = false,
    this.publishedAt,
    this.requiresRepublish = false,
    this.createdAt,
  });

  final String id;
  final String groupId;
  final String organizationId;
  final List<DaySchedule> days;
  final bool isPublished;
  final DateTime? publishedAt;

  /// P-01: this published schedule predates full snapshotting, so its published
  /// preference configuration was never frozen server-side. Publishing once
  /// locks it. Defaults false, so older builds/servers behave unchanged.
  final bool requiresRepublish;
  final DateTime? createdAt;

  DaySchedule? forDay(DayOfWeek day) =>
      days.where((d) => d.day == day).firstOrNull;

  /// Alias for [forDay] — used by student meal provider.
  DaySchedule? scheduleFor(DayOfWeek day) => forDay(day);

  factory MealScheduleModel.fromJson(Map<String, dynamic> j) =>
      MealScheduleModel(
        id: j['id'] ?? '',
        groupId: j['groupId'] ?? '',
        organizationId: j['organizationId'] ?? '',
        days: (j['days'] as List? ?? [])
            .map((d) => DaySchedule.fromJson(d))
            .toList(),
        isPublished: j['isPublished'] ?? false,
        publishedAt: j['publishedAt'] != null
            ? DateTime.parse(j['publishedAt'])
            : null,
        requiresRepublish: j['requiresRepublish'] ?? false,
        createdAt:
            j['createdAt'] != null ? DateTime.parse(j['createdAt']) : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'organizationId': organizationId,
        'days': days.map((d) => d.toJson()).toList(),
        'isPublished': isPublished,
        'publishedAt': publishedAt?.toIso8601String(),
        'requiresRepublish': requiresRepublish,
        'createdAt': createdAt?.toIso8601String(),
      };

  MealScheduleModel copyWith({bool? isPublished, DateTime? publishedAt}) =>
      MealScheduleModel(
        id: id,
        groupId: groupId,
        organizationId: organizationId,
        days: days,
        isPublished: isPublished ?? this.isPublished,
        publishedAt: publishedAt ?? this.publishedAt,
        requiresRepublish: requiresRepublish,
        createdAt: createdAt,
      );
}

/// Alias used by WeeklySchedule references in older code.
typedef WeeklySchedule = MealScheduleModel;

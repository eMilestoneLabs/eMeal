import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// Dynamic meal model — no hardcoded MealType enum.
/// Admin defines slots freely via [slotKey] + [order].
///
/// Images are stored as compressed [Uint8List] bytes locally (≤200 KB total).
/// [imageUrl] is preserved for future backend integration.
@immutable
class MealModel {
  const MealModel({
    required this.id,
    required this.groupId,
    required this.organizationId,
    required this.name,
    required this.slotKey,
    required this.order,
    required this.attendanceWindow,
    required this.isActive,
    this.description,
    this.menuItems = const [],
    this.imageUrl,
    this.imageBytes = const [],
    this.preferencesEnabled = false,
    this.enabledPreferences = const [],
    this.price,
    this.createdAt,
    this.isGeneralAttendance = false,
  });

  final String id;
  final String groupId;
  final String organizationId;
  final String name;
  final String slotKey;       // e.g. "breakfast", "lunch", "iftar"
  final int order;            // admin-set display order
  final MealAttendanceWindow attendanceWindow;
  final bool isActive;
  final String? description;
  final List<String> menuItems;
  /// Future backend image URL (kept for API compat).
  final String? imageUrl;
  /// Locally compressed image bytes — each entry is one compressed image.
  /// Total size must stay ≤ [AppConstants.maxMealImageBytes] (200 KB).
  final List<Uint8List> imageBytes;
  final bool preferencesEnabled;
  final List<String> enabledPreferences;

  /// Additive: master ₹ meal price (integer). Null when pricing disabled/unset.
  final int? price;

  final DateTime? createdAt;

  /// #9/#10: true for the implicit per-group general-attendance slot returned by
  /// /meals/today for attendance-only groups (render a day-level Mark card).
  final bool isGeneralAttendance;

  /// True if at least one local image has been attached.
  bool get hasImages => imageBytes.isNotEmpty;

  /// Single image bytes to display for this meal, from whichever source is
  /// available: a locally-attached image (admin's own session) first, otherwise
  /// the base64 JPEG data URI carried in [imageUrl] (how photos round-trip
  /// through the backend today). Returns null when there's no photo or the
  /// [imageUrl] is a plain network URL (left to network image widgets).
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

  /// The plain network URL for this meal's photo, when [imageUrl] is an http(s)
  /// link (MinIO/CDN) rather than a base64 data URI. Null otherwise. Pairs with
  /// [displayImageBytes] (local/base64) — network image widgets render this.
  String? get networkImageUrl {
    final u = imageUrl;
    if (u != null && (u.startsWith('http://') || u.startsWith('https://'))) {
      return u;
    }
    return null;
  }

  /// True when this meal has a photo from any source (local/base64 or network).
  bool get hasDisplayImage =>
      displayImageBytes != null || networkImageUrl != null;

  /// Total size of all compressed image bytes in bytes.
  int get totalImageBytes =>
      imageBytes.fold(0, (sum, b) => sum + b.length);

  // ── Static helpers ──────────────────────────────────────────────────────────

  static IconData slotIcon(String slotKey) {
    final k = slotKey.toLowerCase();
    if (k.contains('breakfast') || k.contains('morning')) {
      return Icons.free_breakfast_rounded;
    }
    if (k.contains('lunch') || k.contains('afternoon')) {
      return Icons.lunch_dining_rounded;
    }
    if (k.contains('snack') ||
        k.contains('tea') ||
        k.contains('coffee') ||
        k.contains('break')) {
      return Icons.coffee_rounded;
    }
    if (k.contains('dinner') ||
        k.contains('night') ||
        k.contains('supper')) {
      return Icons.dinner_dining_rounded;
    }
    if (k.contains('iftar') ||
        k.contains('sehri') ||
        k.contains('suhoor')) {
      return Icons.nights_stay_rounded;
    }
    return Icons.restaurant_rounded;
  }

  static Color iconBgColor(int order) {
    const palette = [
      Color(0xFFEEF2FF),
      Color(0xFFFFF7ED),
      Color(0xFFF0FDF4),
      Color(0xFFFFF1F2),
      Color(0xFFF0F9FF),
      Color(0xFFFDF4FF),
    ];
    return palette[order % palette.length];
  }

  static Color iconFgColor(int order) {
    const palette = [
      Color(0xFF4F46E5),
      Color(0xFFEA580C),
      Color(0xFF16A34A),
      Color(0xFFE11D48),
      Color(0xFF0284C7),
      Color(0xFF9333EA),
    ];
    return palette[order % palette.length];
  }

  IconData get icon => MealModel.slotIcon(slotKey);

  /// Alias for [preferencesEnabled] — used by meal config form.
  bool get hasPreferences => preferencesEnabled;

  factory MealModel.fromJson(Map<String, dynamic> j) => MealModel(
        id: j['id'] ?? '',
        groupId: j['groupId'] ?? '',
        organizationId: j['organizationId'] ?? '',
        name: j['name'] ?? 'Meal',
        slotKey: j['slotKey'] ?? 'meal',
        order: j['order'] ?? 0,
        attendanceWindow: j['attendanceWindow'] != null
            ? MealAttendanceWindow.fromJson(j['attendanceWindow'])
            : const MealAttendanceWindow(
                openTime: '00:00', closeTime: '23:59'),
        isActive: j['isActive'] ?? true,
        description: j['description'],
        menuItems: List<String>.from(j['menuItems'] ?? []),
        imageUrl: j['imageUrl'],
        // imageBytes not serialised to JSON — in-memory only for local mock
        preferencesEnabled: j['preferencesEnabled'] ?? false,
        enabledPreferences:
            List<String>.from(j['enabledPreferences'] ?? []),
        price: j['price'] is int
            ? j['price'] as int
            : (j['price'] != null
                ? int.tryParse(j['price'].toString())
                : null),
        createdAt:
            j['createdAt'] != null ? DateTime.parse(j['createdAt']) : null,
        isGeneralAttendance: j['isGeneralAttendance'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'organizationId': organizationId,
        'name': name,
        'slotKey': slotKey,
        'order': order,
        'attendanceWindow': attendanceWindow.toJson(),
        'isActive': isActive,
        'description': description,
        'menuItems': menuItems,
        'imageUrl': imageUrl,
        'preferencesEnabled': preferencesEnabled,
        'enabledPreferences': enabledPreferences,
        'price': price,
        'isGeneralAttendance': isGeneralAttendance,
      };

  MealModel copyWith({
    String? name,
    String? slotKey,
    int? order,
    MealAttendanceWindow? attendanceWindow,
    bool? isActive,
    String? description,
    List<String>? menuItems,
    String? imageUrl,
    List<Uint8List>? imageBytes,
    bool? preferencesEnabled,
    List<String>? enabledPreferences,
    int? price,
    bool? isGeneralAttendance,
  }) =>
      MealModel(
        id: id,
        groupId: groupId,
        organizationId: organizationId,
        name: name ?? this.name,
        slotKey: slotKey ?? this.slotKey,
        order: order ?? this.order,
        attendanceWindow: attendanceWindow ?? this.attendanceWindow,
        isActive: isActive ?? this.isActive,
        description: description ?? this.description,
        menuItems: menuItems ?? this.menuItems,
        imageUrl: imageUrl ?? this.imageUrl,
        imageBytes: imageBytes ?? this.imageBytes,
        preferencesEnabled: preferencesEnabled ?? this.preferencesEnabled,
        enabledPreferences: enabledPreferences ?? this.enabledPreferences,
        price: price ?? this.price,
        createdAt: createdAt,
        isGeneralAttendance: isGeneralAttendance ?? this.isGeneralAttendance,
      );
}

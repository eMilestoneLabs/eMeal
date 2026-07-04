import 'package:flutter/foundation.dart';

/// Module 22 (Pass 9) — Member-Hosted Guests (+N).
///
/// Mirrors the backend guest serializer (GuestsService.toResponse —
/// CONTRACT-LOCKED):
///   { id, groupId, mealId, attendanceDate (YYYY-MM-DD), hostUserId, isAdult,
///     displayName, mealPreference, status, pendingApproval, priceSnapshot,
///     createdBy, createdAt }

int? _asIntOrNull(dynamic v) =>
    v == null ? null : (v is int ? v : int.tryParse(v.toString()));

@immutable
class MealGuestModel {
  const MealGuestModel({
    required this.id,
    required this.groupId,
    required this.mealId,
    required this.attendanceDate,
    required this.hostUserId,
    required this.isAdult,
    required this.status,
    required this.pendingApproval,
    required this.createdBy,
    this.displayName,
    this.mealPreference,
    this.priceSnapshot,
    this.createdAt,
  });

  final String id;
  final String groupId;
  final String mealId;

  /// YYYY-MM-DD, exactly as the backend sends it.
  final String attendanceDate;
  final String hostUserId;
  final bool isAdult;
  final String? displayName;
  final String? mealPreference;

  /// booked | cancelled | no_show.
  final String status;

  /// True while awaiting admin approval OR host confirmation (FR-HG-042/062).
  final bool pendingApproval;

  /// ₹ snapshot at booking; null = headcount-only (pricing off).
  final int? priceSnapshot;
  final String createdBy;
  final DateTime? createdAt;

  bool get isBooked => status == 'booked';
  bool get isCancelled => status == 'cancelled';

  /// FR-HG-062: an admin proposed this guest — the HOST must confirm/decline.
  bool get isAdminProposed => createdBy != hostUserId;

  /// Active pending row (booked + awaiting a decision).
  bool get isPending => isBooked && pendingApproval;

  /// Counts toward kitchen plates + billing (booked and fully approved).
  bool get isConfirmed => isBooked && !pendingApproval;

  String get typeLabel => isAdult ? 'Adult' : 'Child';

  factory MealGuestModel.fromJson(Map<String, dynamic> j) => MealGuestModel(
        id: j['id']?.toString() ?? '',
        groupId: j['groupId']?.toString() ?? '',
        mealId: j['mealId']?.toString() ?? '',
        attendanceDate: j['attendanceDate']?.toString() ?? '',
        hostUserId: j['hostUserId']?.toString() ?? '',
        isAdult: j['isAdult'] ?? true,
        displayName: j['displayName']?.toString(),
        mealPreference: j['mealPreference']?.toString(),
        status: j['status']?.toString() ?? 'booked',
        pendingApproval: j['pendingApproval'] ?? false,
        priceSnapshot: _asIntOrNull(j['priceSnapshot']),
        createdBy: j['createdBy']?.toString() ?? '',
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'].toString())?.toLocal()
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'groupId': groupId,
        'mealId': mealId,
        'attendanceDate': attendanceDate,
        'hostUserId': hostUserId,
        'isAdult': isAdult,
        'displayName': displayName,
        'mealPreference': mealPreference,
        'status': status,
        'pendingApproval': pendingApproval,
        'priceSnapshot': priceSnapshot,
        'createdBy': createdBy,
        'createdAt': createdAt?.toIso8601String(),
      };
}

/// One draft guest row in a booking request (FR-HG-031).
@immutable
class GuestDraft {
  const GuestDraft({
    this.isAdult = true,
    this.displayName,
    this.mealPreference,
  });

  final bool isAdult;
  final String? displayName;
  final String? mealPreference;

  GuestDraft copyWith({
    bool? isAdult,
    String? displayName,
    String? mealPreference,
  }) =>
      GuestDraft(
        isAdult: isAdult ?? this.isAdult,
        displayName: displayName ?? this.displayName,
        mealPreference: mealPreference ?? this.mealPreference,
      );

  Map<String, dynamic> toJson() => {
        'isAdult': isAdult,
        if (displayName != null && displayName!.trim().isNotEmpty)
          'displayName': displayName!.trim(),
        if (mealPreference != null) 'mealPreference': mealPreference,
      };
}

/// Booking response — mirrors POST /attendance/:mealId/guests.
@immutable
class GuestBookingResult {
  const GuestBookingResult({
    required this.guests,
    required this.guestAdults,
    required this.guestChildren,
    required this.pendingApproval,
    required this.estimatedGuestCost,
  });

  final List<MealGuestModel> guests;
  final int guestAdults;
  final int guestChildren;
  final int pendingApproval;
  final int estimatedGuestCost;

  factory GuestBookingResult.fromJson(Map<String, dynamic> j) {
    final counters =
        (j['counters'] as Map?)?.cast<String, dynamic>() ?? const {};
    return GuestBookingResult(
      guests: ((j['guests'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => MealGuestModel.fromJson(e.cast<String, dynamic>()))
          .toList(),
      guestAdults: _asIntOrNull(counters['guestAdults']) ?? 0,
      guestChildren: _asIntOrNull(counters['guestChildren']) ?? 0,
      pendingApproval: _asIntOrNull(counters['pendingApproval']) ?? 0,
      estimatedGuestCost: _asIntOrNull(j['estimatedGuestCost']) ?? 0,
    );
  }
}

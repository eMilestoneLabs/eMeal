import 'package:flutter/foundation.dart';

/// Member Billing V2 contract — mirrors the backend
/// GET /api/v1/attendance/billing-summary response: { summary, mealBreakdown[], members[] }.
/// Revenue uses the per-record price SNAPSHOT (present-only).

int _asInt(dynamic v) => v is int
    ? v
    : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

@immutable
class BillingMemberRow {
  const BillingMemberRow({
    required this.userId,
    required this.userName,
    required this.role,
    required this.totalBill,
    required this.presentCount,
    required this.skippedCount,
    required this.absentCount,
    this.email,
    this.phone,
    this.lastActivity,
  });

  final String userId;
  final String userName;
  final String role;
  final int totalBill;
  final int presentCount;
  final int skippedCount;
  final int absentCount;

  /// Additive: included so admins can search members by email / phone.
  final String? email;
  final String? phone;

  final DateTime? lastActivity;

  int get totalMeals => presentCount + skippedCount + absentCount;

  factory BillingMemberRow.fromJson(Map<String, dynamic> j) => BillingMemberRow(
        userId: j['userId']?.toString() ?? '',
        userName: j['userName']?.toString() ?? '',
        role: j['role']?.toString() ?? 'member',
        totalBill: _asInt(j['totalBill']),
        presentCount: _asInt(j['presentCount']),
        skippedCount: _asInt(j['skippedCount']),
        absentCount: _asInt(j['absentCount']),
        email: j['email']?.toString(),
        phone: j['phone']?.toString(),
        lastActivity: j['lastActivity'] != null
            ? DateTime.tryParse(j['lastActivity'].toString())?.toLocal()
            : null,
      );
}

@immutable
class BillingMealBreakdown {
  const BillingMealBreakdown({
    required this.mealId,
    required this.mealName,
    required this.revenue,
    required this.presentCount,
  });

  final String mealId;
  final String mealName;
  final int revenue;
  final int presentCount;

  factory BillingMealBreakdown.fromJson(Map<String, dynamic> j) =>
      BillingMealBreakdown(
        mealId: j['mealId']?.toString() ?? '',
        mealName: j['mealName']?.toString() ?? '',
        revenue: _asInt(j['revenue']),
        presentCount: _asInt(j['presentCount']),
      );
}

@immutable
class BillingSummaryV2 {
  const BillingSummaryV2({
    required this.revenue,
    required this.memberCount,
    required this.presentMeals,
    required this.skippedMeals,
    required this.absentMeals,
    required this.averageBill,
    required this.mealBreakdown,
    required this.members,
  });

  final int revenue;
  final int memberCount;
  final int presentMeals;
  final int skippedMeals;
  final int absentMeals;
  final int averageBill;
  final List<BillingMealBreakdown> mealBreakdown;
  final List<BillingMemberRow> members;

  static const BillingSummaryV2 empty = BillingSummaryV2(
    revenue: 0,
    memberCount: 0,
    presentMeals: 0,
    skippedMeals: 0,
    absentMeals: 0,
    averageBill: 0,
    mealBreakdown: [],
    members: [],
  );

  factory BillingSummaryV2.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BillingSummaryV2(
      revenue: _asInt(s['revenue']),
      memberCount: _asInt(s['memberCount']),
      presentMeals: _asInt(s['presentMeals']),
      skippedMeals: _asInt(s['skippedMeals']),
      absentMeals: _asInt(s['absentMeals']),
      averageBill: _asInt(s['averageBill']),
      mealBreakdown: ((j['mealBreakdown'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BillingMealBreakdown.fromJson(e.cast<String, dynamic>()))
          .toList(),
      members: ((j['members'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BillingMemberRow.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }
}

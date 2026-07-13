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
    this.guestCount = 0,
    this.guestAmount = 0,
    this.vacationDays = 0,
    this.adjustmentsTotal = 0,
    this.openingBalance = 0,
    int? netBill,
    this.email,
    this.phone,
    this.lastActivity,
  }) : netBill = netBill ?? totalBill;

  final String userId;
  final String userName;
  final String role;
  final int totalBill;
  final int presentCount;
  final int skippedCount;
  final int absentCount;

  /// Module 22 (FR-HG-050/053, Pass 9): hosted-guest charges itemised
  /// separately — already INCLUDED in [totalBill], never double-counted.
  final int guestCount;
  final int guestAmount;

  /// Pass 12 (FR-BILLX-012): vacation days — reported separately, never billed.
  final int vacationDays;

  /// Pass 12 (FR-BILLX-030/031) + REF-001 (2026-07-13): signed append-only
  /// ledger total for the range (debit AND refund +, credit −) and the
  /// resulting net bill.
  final int adjustmentsTotal;

  /// CREDIT-001 (2026-07-13): balance carried forward from the previous
  /// FINALIZED billing period (credit negative, dues positive). Display
  /// item — ALREADY included in [netBill].
  final int openingBalance;
  final int netBill;

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
        guestCount: _asInt(j['guestCount']),
        guestAmount: _asInt(j['guestAmount']),
        vacationDays: _asInt(j['vacationDays']),
        adjustmentsTotal: _asInt(j['adjustmentsTotal']),
        openingBalance: _asInt(j['openingBalance']),
        netBill: j['netBill'] != null ? _asInt(j['netBill']) : null,
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

/// Pass 12 (FR-BILLX-021): per-slot rollup row.
@immutable
class BillingSlotBreakdown {
  const BillingSlotBreakdown({
    required this.slotKey,
    required this.presentCount,
    required this.revenue,
  });

  final String slotKey;
  final int presentCount;
  final int revenue;

  factory BillingSlotBreakdown.fromJson(Map<String, dynamic> j) =>
      BillingSlotBreakdown(
        slotKey: j['slotKey']?.toString() ?? 'general',
        presentCount: _asInt(j['presentCount']),
        revenue: _asInt(j['revenue']),
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
    this.guestRevenue = 0,
    this.adjustmentsTotal = 0,
    this.openingBalanceTotal = 0,
    int? netRevenue,
    this.vacationDays = 0,
    this.slotBreakdown = const [],
    this.periodFrom,
    this.periodTo,
    this.cycleStartDay,
  }) : netRevenue = netRevenue ?? revenue;

  final int revenue;
  final int memberCount;
  final int presentMeals;
  final int skippedMeals;
  final int absentMeals;
  final int averageBill;

  /// Module 22 (FR-HG-050, Pass 9): hosted-guest revenue — a slice of
  /// [revenue] (already included), itemised for the summary card.
  final int guestRevenue;

  /// Pass 12 (FR-BILLX-030/012/021): ledger + vacation transparency and the
  /// per-slot rollup; period echoes what range the backend actually used
  /// (billing-cycle default when no explicit range was sent).
  final int adjustmentsTotal;

  /// CREDIT-001: group-wide carried-forward total (each member's share is
  /// already inside their netBill).
  final int openingBalanceTotal;
  final int netRevenue;
  final int vacationDays;
  final List<BillingSlotBreakdown> slotBreakdown;
  final String? periodFrom; // YYYY-MM-DD
  final String? periodTo; // YYYY-MM-DD
  final int? cycleStartDay;
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
      guestRevenue: _asInt(s['guestRevenue']),
      adjustmentsTotal: _asInt(s['adjustmentsTotal']),
      openingBalanceTotal: _asInt(s['openingBalanceTotal']),
      netRevenue: s['netRevenue'] != null ? _asInt(s['netRevenue']) : null,
      vacationDays: _asInt(s['vacationDays']),
      slotBreakdown: ((j['slotBreakdown'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => BillingSlotBreakdown.fromJson(e.cast<String, dynamic>()))
          .toList(),
      periodFrom: (j['period'] as Map?)?['fromDate']?.toString(),
      periodTo: (j['period'] as Map?)?['toDate']?.toString(),
      cycleStartDay: (j['period'] as Map?)?['cycleStartDay'] is num
          ? ((j['period'] as Map)['cycleStartDay'] as num).toInt()
          : null,
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

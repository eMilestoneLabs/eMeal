import 'package:flutter/foundation.dart';

/// Issue 5 (FR-BILLX-043) — a member's OWN bill as computed by the SAME backend
/// engine as the admin Member-Billing dashboard (GET /attendance/my-billing).
/// All amounts are whole ₹. `netBill = mealCharges + guestAmount +
/// adjustmentsTotal`, so the student's total reconciles exactly with the admin.
@immutable
class MyBilling {
  const MyBilling({
    this.presentCount = 0,
    this.skippedCount = 0,
    this.absentCount = 0,
    this.vacationDays = 0,
    this.mealCharges = 0,
    this.guestCount = 0,
    this.guestAmount = 0,
    this.adjustmentsTotal = 0,
    this.debitsTotal = 0,
    this.creditsTotal = 0,
    this.refundsTotal = 0,
    this.billSkippedMeals = false,
    this.openingBalance = 0,
    this.totalBill = 0,
    int? netBill,
    this.periodFrom,
    this.periodTo,
  }) : netBill = netBill ?? totalBill;

  final int presentCount;
  final int skippedCount;
  final int absentCount;
  final int vacationDays;

  /// Own meal charges (present-only price snapshots), in ₹.
  final int mealCharges;

  /// Hosted-guest charges billed to this member, in ₹.
  final int guestCount;
  final int guestAmount;

  /// Signed ledger total (REF-001: debit AND refund +, credit −), in ₹.
  final int adjustmentsTotal;

  /// Live-Test-5 ISSUE-4 (enterprise display policy): itemised ledger
  /// components — each financial concept is its own line item, never merged.
  /// All positive magnitudes; signs are applied at display time
  /// (debit +, credit −, refund + per REF-001: a refund returns credit as cash).
  final int debitsTotal;
  final int creditsTotal;
  final int refundsTotal;

  /// Group policy: whether skipped/absent meals are billed this period —
  /// lets rows show the real charged amount ("Billed") instead of ₹0.
  final bool billSkippedMeals;

  /// CREDIT-001: balance carried forward from the previous finalized billing
  /// period (credit negative, dues positive) — already included in [netBill].
  final int openingBalance;

  /// mealCharges + guestAmount (pre-adjustment) and the final net.
  final int totalBill;
  final int netBill;

  final String? periodFrom;
  final String? periodTo;

  static const MyBilling empty = MyBilling();

  static int _i(dynamic v) => v is int
      ? v
      : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

  factory MyBilling.fromJson(Map<String, dynamic> j) {
    final period = (j['period'] as Map?)?.cast<String, dynamic>();
    return MyBilling(
      presentCount: _i(j['presentCount']),
      skippedCount: _i(j['skippedCount']),
      absentCount: _i(j['absentCount']),
      vacationDays: _i(j['vacationDays']),
      mealCharges: _i(j['mealCharges']),
      guestCount: _i(j['guestCount']),
      guestAmount: _i(j['guestAmount']),
      adjustmentsTotal: _i(j['adjustmentsTotal']),
      debitsTotal: _i(j['debitsTotal']),
      creditsTotal: _i(j['creditsTotal']),
      refundsTotal: _i(j['refundsTotal']),
      billSkippedMeals: j['billSkippedMeals'] == true,
      openingBalance: _i(j['openingBalance']),
      totalBill: _i(j['totalBill']),
      netBill: j['netBill'] != null ? _i(j['netBill']) : null,
      periodFrom: period?['fromDate']?.toString(),
      periodTo: period?['toDate']?.toString(),
    );
  }
}

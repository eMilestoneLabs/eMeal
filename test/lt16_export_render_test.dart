// Issues_Live_Test_16 ISSUE-11/16/1 — the polished PDF and the Excel
// workbook actually RENDER (layout errors only surface at render time).
import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

BillingRow _row(int i, {String? pref}) => BillingRow(
      userId: 'u${i % 7}',
      userName: 'Member ${i % 7} with a rather long display name',
      mealId: 'm${i % 3}',
      mealName: i.isEven ? 'Breakfast' : '—',
      status: AttendanceStatus.values[i % 3],
      preference: pref,
      price: 60,
      date: DateTime(2026, 9, 1 + (i % 28)),
      markedAt: i.isEven ? DateTime(2026, 9, 1, 8, 30) : null,
      autoSkipped: false,
    );

BillingSummary _sum(int i) => BillingSummary(
      userId: 'u$i',
      userName: 'Member $i',
      present: 20,
      absent: 2,
      skipped: 3,
      totalBill: 1200,
      consumedByMeal: const {'Breakfast': 10, 'Lunch': 10},
    );

final _adjustments = [
  ExportAdjustment.fromApi({
    'userId': 'u1',
    'entryDate': '2026-09-20',
    'type': 'credit',
    'amount': 12550,
    'reason': 'Advance paid in cash — 30 ch',
    'status': 'posted',
  }),
  ExportAdjustment.fromApi({
    'userId': 'u2',
    'entryDate': '2026-09-02',
    'type': 'debit',
    'amount': 5000,
    'reason': '',
    'status': 'pending',
  }),
];

void main() {
  final rows = [for (var i = 0; i < 600; i++) _row(i, pref: i % 5 == 0 ? null : 'Veg')];
  final summaries = [for (var i = 0; i < 7; i++) _sum(i)];
  final fin = {
    'u1': const MemberExportFinancials(
        guestCount: 2, guestAmount: 120, adjustmentsTotal: -125, openingBalance: 40),
  };

  test('priced PDF renders (multi-page, adjustments, empty cells)', () async {
    final bytes = await buildReportBytesForTest(
      pdf: true,
      rows: rows,
      summaries: summaries,
      pricingEnabled: true,
      financialsByUser: fin,
      adjustments: _adjustments,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(10000));
  });

  test('unpriced PDF renders with the 7-column layout', () async {
    final bytes = await buildReportBytesForTest(
      pdf: true,
      rows: rows.take(20).toList(),
      summaries: summaries,
      pricingEnabled: false,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('empty report still renders (no rows, no summaries)', () async {
    final bytes = await buildReportBytesForTest(
      pdf: true,
      rows: const [],
      summaries: const [],
      pricingEnabled: true,
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('XLSX carries an Adjustments sheet with the Reason column', () async {
    final bytes = await buildReportBytesForTest(
      pdf: false,
      rows: rows.take(30).toList(),
      summaries: summaries,
      pricingEnabled: true,
      financialsByUser: fin,
      adjustments: _adjustments,
    );
    final book = xls.Excel.decodeBytes(bytes);
    expect(book.tables.keys, containsAll(['Billing Summary', 'Attendance', 'Adjustments']));
    final sheet = book.tables['Adjustments']!;
    final header = sheet.rows
        .map((r) => r.map((c) => c?.value?.toString() ?? '').toList())
        .firstWhere((r) => r.contains('Reason'));
    expect(header, ['Date', 'Member', 'Type', 'Amount (₹)', 'Reason', 'Status']);
    final flat = sheet.rows
        .expand((r) => r.map((c) => c?.value?.toString() ?? ''))
        .toList();
    expect(flat, contains('Advance paid in cash — 30 ch'));
    expect(flat, contains('-₹125.50'));
    // Sorted by date: the 02/09 entry precedes the 20/09 entry.
    expect(flat.indexOf('02/09/2026'), lessThan(flat.indexOf('20/09/2026')));
  });

  test('unpriced XLSX has NO Adjustments sheet (no ledger)', () async {
    final bytes = await buildReportBytesForTest(
      pdf: false,
      rows: rows.take(5).toList(),
      summaries: summaries,
      pricingEnabled: false,
      adjustments: _adjustments,
    );
    expect(xls.Excel.decodeBytes(bytes).tables.keys, isNot(contains('Adjustments')));
  });
}

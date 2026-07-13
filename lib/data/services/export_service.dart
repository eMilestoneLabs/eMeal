import 'dart:io';
import 'package:smart_meal_management/core/utils/time_format.dart';
import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

/// Builds PDF / CSV / Excel exports of attendance + billing and shares them via
/// the platform share sheet (share_plus).
/// Host-inclusive financial extras for one member, so export summaries carry
/// the SAME money story as the billing screens: hosted-guest charges are
/// billed to the host, adjustments are the signed ledger total, and
/// **Net Total = meals + guests + adjustments**.
class MemberExportFinancials {
  const MemberExportFinancials({
    this.guestCount = 0,
    this.guestAmount = 0,
    this.adjustmentsTotal = 0,
    this.openingBalance = 0,
  });

  final int guestCount;
  final int guestAmount;
  final int adjustmentsTotal;

  /// CREDIT-001 (2026-07-13): balance carried forward from the previous
  /// finalized billing period — included in the Net Total.
  final int openingBalance;

  bool get hasAny =>
      guestAmount != 0 || adjustmentsTotal != 0 || openingBalance != 0;

  int netFor(int mealsBill) =>
      openingBalance + mealsBill + guestAmount + adjustmentsTotal;

  String openingLabel(String currency) =>
      '${openingBalance > 0 ? '+' : '-'}$currency${openingBalance.abs()}';

  String adjustmentsLabel(String currency) =>
      '${adjustmentsTotal > 0 ? '+' : '-'}$currency${adjustmentsTotal.abs()}';

  static String net(String currency, int v) =>
      v < 0 ? '-$currency${-v}' : '$currency$v';
}

class ExportService {
  ExportService._();

  static final ExportService instance = ExportService._();

  /// FR-EXP-042 (ISSUE-14): brand line stamped on every export (PDF/XLSX/CSV).
  static const String brandLine = 'MealAttend · Powered by eMilestone';

  /// FR-EXP-043 / FR-ANL-031: timezone label the report's dates are rendered
  /// in (device local — all record timestamps are converted locally),
  /// e.g. "IST (UTC+05:30)".
  static String tzLabel() {
    final now = DateTime.now();
    final off = now.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final h = off.inHours.abs().toString().padLeft(2, '0');
    final m = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${now.timeZoneName} (UTC$sign$h:$m)';
  }

  /// FR-EXP-042/043: one-line report metadata — scope, period, timezone,
  /// generated-at. Used in PDF headers/footers and XLSX/CSV metadata rows.
  String _metaLine({required String scopeLabel, String? periodLabel}) =>
      '$scopeLabel'
      '${periodLabel != null ? '  |  Period: $periodLabel' : ''}'
      '  |  Timezone: ${tzLabel()}'
      '  |  Generated: ${_formatDateTime(DateTime.now())}';

  /// FR-EXP-042: A4 page theme with the translucent diagonal brand watermark.
  pw.PageTheme _brandedPageTheme() => pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        buildBackground: (context) => pw.Center(
          child: pw.Transform.rotate(
            angle: 0.6,
            child: pw.Opacity(
              opacity: 0.05,
              child: pw.Text(
                'MealAttend',
                style: pw.TextStyle(
                  fontSize: 88,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo,
                ),
              ),
            ),
          ),
        ),
      );

  /// FR-EXP-042: branded footer with page numbers on every PDF page.
  pw.Widget _brandedFooter(pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Divider(color: PdfColors.grey400, height: 8),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(brandLine, style: const pw.TextStyle(fontSize: 8)),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ],
      );

  List<String> _headers(bool pricingEnabled) => [
        'Name',
        'Group',
        'Meal',
        'Status',
        'Preference',
        if (pricingEnabled) 'Price Tag',
        'Date',
        'Attendance Marked Time',
      ];

  List<String> _rowCells(
    BillingRow r,
    String groupName,
    bool pricingEnabled, {
    // The bundled PDF font cannot render the ₹ glyph, so the PDF passes 'Rs '.
    // CSV/Excel keep '₹' (those render it correctly).
    String currency = '₹',
  }) {
    return [
      r.userName,
      groupName,
      r.mealName,
      _statusLabel(r.status),
      r.preference ?? '',
      // Only PRESENT meals carry a charge — Skip / Absent show 0 so the column
      // matches the billing total.
      if (pricingEnabled)
        (r.status == AttendanceStatus.present
            ? '$currency${r.price ?? 0}'
            : '${currency}0'),
      _formatDate(r.date),
      r.markedAt != null ? _formatDateTime(r.markedAt!) : '',
    ];
  }

  // ── PDF ────────────────────────────────────────────────────────────────────

  Future<void> exportPdf({
    required List<AttendanceModel> records,
    required List<MealModel> meals,
    required String groupName,
    required bool pricingEnabled,
    required DateTime from,
    required DateTime to,
    String? dateRangeLabel,
    List<MealModel> todayMeals = const [],
    Set<String> vacationUserIds = const {},
    // Guest + adjustment figures per userId — when provided, each member's
    // summary block itemises Meals / Hosted guests / Adjustments / Net Total,
    // reconciling exactly with the billing screens.
    Map<String, MemberExportFinancials> financialsByUser = const {},
    // SRS Module 03 (survey Q17/Q22): group Bill-Skip policy — bills
    // Absent/Skipped rows at their scheduled price when true.
    bool billSkippedMeals = false,
  }) async {
    // Issue 3 & 7: pass today's published overlay + vacation members so exported
    // billing matches the on-screen figures (per-day window auto-skip + vacation
    // exclusion) instead of the master-window / no-vacation fallback.
    final rows = BillingService.buildRows(
      records: records,
      meals: meals,
      from: from,
      to: to,
      todayMeals: todayMeals,
      vacationUserIds: vacationUserIds,
    );
    final summaries =
        BillingService.summarize(rows, billSkippedMeals: billSkippedMeals);
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        // FR-EXP-042: branded page theme (diagonal watermark) + footer.
        pageTheme: _brandedPageTheme(),
        footer: _brandedFooter,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MealAttend — Attendance Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            // FR-EXP-043: period + timezone + generated-at on the header.
            pw.Text(
              _metaLine(
                scopeLabel: 'Group: $groupName',
                periodLabel: dateRangeLabel,
              ),
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Divider(),
          ],
        ),
        // FR-EXP-041 (ISSUE-14): Summary FIRST, detailed line-items second.
        build: (context) => [
          pw.Text(
            'Billing Summary',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          ...summaries.map((s) =>
              _pdfSummaryBlock(s, pricingEnabled, financialsByUser[s.userId])),
          pw.SizedBox(height: 18),
          pw.Text(
            'Detailed Records',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: _headers(pricingEnabled),
            data: rows
                .map((r) =>
                    _rowCells(r, groupName, pricingEnabled, currency: 'Rs '))
                .toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.indigo100),
            oddRowDecoration:
                const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
        ],
      ),
    );

    await _shareBytes(
      await pdf.save(),
      'attendance_${_safe(groupName)}_${_stamp()}.pdf',
      'Attendance Report — $groupName',
    );
  }

  pw.Widget _pdfSummaryBlock(
    BillingSummary s,
    bool pricingEnabled,
    MemberExportFinancials? fin,
  ) {
    final consumed = s.consumedByMeal.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('   ·   ');
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(s.userName,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
          pw.SizedBox(height: 2),
          if (consumed.isNotEmpty)
            pw.Text(consumed, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 2),
          pw.Text(
            'Present: ${s.present}   Skipped: ${s.skipped}   Absent: ${s.absent}   Total meals: ${s.totalMeals}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (pricingEnabled) ...[
            pw.SizedBox(height: 2),
            if (fin == null || !fin.hasAny)
              pw.Text(
                // PDF font lacks ₹ — use 'Rs '.
                'Total Bill: Rs ${s.totalBill}',
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              )
            else ...[
              // Host-inclusive breakdown — identical to the billing screens.
              pw.Text('Meals: Rs ${s.totalBill}',
                  style: const pw.TextStyle(fontSize: 9)),
              if (fin.guestAmount != 0)
                pw.Text(
                  'Hosted guests (${fin.guestCount}) — billed to this host: Rs ${fin.guestAmount}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if (fin.openingBalance != 0)
                pw.Text(
                  'Opening balance (carried forward): ${fin.openingLabel('Rs ')}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              if (fin.adjustmentsTotal != 0)
                pw.Text(
                  'Adjustments (credits / refunds): ${fin.adjustmentsLabel('Rs ')}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              pw.Text(
                'Net Total: ${MemberExportFinancials.net('Rs ', fin.netFor(s.totalBill))}',
                style:
                    pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // SRS Module 03 RPT-001: CSV export removed — Excel multi-sheet + optional
  // PDF are the only supported formats.

  // ── Excel (.xlsx) ────────────────────────────────────────────────────────────

  Future<void> exportXlsx({
    required List<AttendanceModel> records,
    required List<MealModel> meals,
    required String groupName,
    required bool pricingEnabled,
    required DateTime from,
    required DateTime to,
    String? dateRangeLabel,
    List<MealModel> todayMeals = const [],
    Set<String> vacationUserIds = const {},
    Map<String, MemberExportFinancials> financialsByUser = const {},
    // SRS Module 03 (survey Q17/Q22): group Bill-Skip policy.
    bool billSkippedMeals = false,
  }) async {
    final rows = BillingService.buildRows(
        records: records,
        meals: meals,
        from: from,
        to: to,
        todayMeals: todayMeals,
        vacationUserIds: vacationUserIds);
    final summaries =
        BillingService.summarize(rows, billSkippedMeals: billSkippedMeals);

    final book = xls.Excel.createExcel();

    // FR-EXP-042/043: brand + metadata band at the top of a sheet.
    void brandBand(xls.Sheet sheet) {
      sheet.appendRow([xls.TextCellValue(brandLine)]);
      sheet.appendRow([
        xls.TextCellValue(_metaLine(
          scopeLabel: 'Group: $groupName',
          periodLabel: dateRangeLabel,
        )),
      ]);
      sheet.appendRow([xls.TextCellValue('')]);
    }

    // FR-EXP-041 (ISSUE-14): the Billing Summary sheet comes FIRST and is the
    // default sheet the workbook opens on; detailed rows are secondary.
    // With per-member financials the money columns split into the full
    // host-inclusive breakdown (Meals / Guests / Adjustments / Net Total) so
    // the sheet reconciles with the billing screens; otherwise the legacy
    // single "Total Bill" column is preserved exactly.
    final withFinancials =
        pricingEnabled && financialsByUser.values.any((f) => f.hasAny);
    final sum = book['Billing Summary'];
    brandBand(sum);
    sum.appendRow([
      xls.TextCellValue('Name'),
      xls.TextCellValue('Present'),
      xls.TextCellValue('Skipped'),
      xls.TextCellValue('Absent'),
      xls.TextCellValue('Total Meals'),
      if (pricingEnabled && !withFinancials) xls.TextCellValue('Total Bill'),
      if (withFinancials) ...[
        xls.TextCellValue('Meals (₹)'),
        xls.TextCellValue('Hosted Guests (billed to host) (₹)'),
        xls.TextCellValue('Opening Balance (₹)'),
        xls.TextCellValue('Adjustments (₹)'),
        xls.TextCellValue('Net Total (₹)'),
      ],
    ]);
    for (final s in summaries) {
      final fin = financialsByUser[s.userId] ?? const MemberExportFinancials();
      sum.appendRow([
        xls.TextCellValue(s.userName),
        xls.TextCellValue('${s.present}'),
        xls.TextCellValue('${s.skipped}'),
        xls.TextCellValue('${s.absent}'),
        xls.TextCellValue('${s.totalMeals}'),
        if (pricingEnabled && !withFinancials)
          xls.TextCellValue('₹${s.totalBill}'),
        if (withFinancials) ...[
          xls.TextCellValue('${s.totalBill}'),
          xls.TextCellValue('${fin.guestAmount}'),
          xls.TextCellValue('${fin.openingBalance}'),
          xls.TextCellValue('${fin.adjustmentsTotal}'),
          xls.TextCellValue('${fin.netFor(s.totalBill)}'),
        ],
      ]);
    }

    final sheet = book['Attendance'];
    brandBand(sheet);
    sheet.appendRow(
      _headers(pricingEnabled).map((h) => xls.TextCellValue(h)).toList(),
    );
    for (final r in rows) {
      sheet.appendRow(
        _rowCells(r, groupName, pricingEnabled)
            .map((c) => xls.TextCellValue(c))
            .toList(),
      );
    }

    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');
    book.setDefaultSheet('Billing Summary');

    final bytes = book.encode();
    if (bytes == null) {
      throw Exception('Failed to encode Excel file');
    }
    await _shareBytes(
      bytes,
      'attendance_${_safe(groupName)}_${_stamp()}.xlsx',
      'Attendance Export — $groupName',
    );
  }

  // ── Event Guest Export (unchanged) ──────────────────────────────────────────

  Future<void> exportEventGuestsPdf({
    required List<EventGuestParty> parties,
    required String eventName,
    String? eventDateLabel,
  }) async {
    final pdf = pw.Document();

    final rows = <List<String>>[];
    for (final party in parties) {
      for (final person in party.persons) {
        rows.add([
          party.primaryName,
          person.displayName,
          person.isAdult ? 'Adult' : 'Child',
          person.isPresent ? 'Present' : 'Absent',
          person.mealPreference?.label ?? person.selectedMealTypeId ?? '—',
        ]);
      }
    }

    final totalGuests = parties.fold(0, (s, p) => s + p.totalCount);
    final totalAdults = parties.fold(0, (s, p) => s + p.adultsCount);
    final totalChildren = parties.fold(0, (s, p) => s + p.childrenCount);
    final totalVeg = parties.fold(0, (s, p) => s + p.vegCount);
    final totalNonVeg = parties.fold(0, (s, p) => s + p.nonVegCount);

    pdf.addPage(
      pw.MultiPage(
        // FR-EXP-042: branded page theme (diagonal watermark) + footer.
        pageTheme: _brandedPageTheme(),
        footer: _brandedFooter,
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MealAttend — Event Guest Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            // FR-EXP-041: summary figures first — the headline counts.
            pw.Text(
              'Guests: $totalGuests  |  Adults: $totalAdults  |  Children: $totalChildren'
              '  |  Veg: $totalVeg  |  Non-Veg: $totalNonVeg',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 4),
            // FR-EXP-043: date + timezone + generated-at on the header.
            pw.Text(
              _metaLine(
                scopeLabel: 'Event: $eventName',
                periodLabel: eventDateLabel,
              ),
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: const ['Party', 'Name', 'Type', 'Attendance', 'Meal'],
            data: rows,
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.purple100),
            oddRowDecoration:
                const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
        ],
      ),
    );

    await _shareBytes(
      await pdf.save(),
      'event_guests_${_safe(eventName)}_${_stamp()}.pdf',
      'Guest Report — $eventName',
    );
  }

  /// SRS Module 03 RPT-001: the event guest spreadsheet is an Excel (.xlsx)
  /// workbook — CSV is no longer supported anywhere in the app.
  Future<void> exportEventGuestsXlsx({
    required List<EventGuestParty> parties,
    required String eventName,
    String? eventDateLabel,
  }) async {
    final book = xls.Excel.createExcel();
    final sheet = book['Guest List'];

    // FR-EXP-042/043 (ISSUE-14): brand + metadata band at the top.
    sheet.appendRow([xls.TextCellValue(brandLine)]);
    sheet.appendRow([
      xls.TextCellValue(
          _metaLine(scopeLabel: 'Event: $eventName', periodLabel: eventDateLabel)),
    ]);
    sheet.appendRow([xls.TextCellValue('')]);
    sheet.appendRow([
      xls.TextCellValue('Party'),
      xls.TextCellValue('Name'),
      xls.TextCellValue('Type'),
      xls.TextCellValue('Attendance'),
      xls.TextCellValue('Meal Preference'),
      xls.TextCellValue('Party Total'),
    ]);

    for (final party in parties) {
      for (final person in party.persons) {
        sheet.appendRow([
          xls.TextCellValue(party.primaryName),
          xls.TextCellValue(person.displayName),
          xls.TextCellValue(person.isAdult ? 'Adult' : 'Child'),
          xls.TextCellValue(person.isPresent ? 'Present' : 'Absent'),
          xls.TextCellValue(
              person.mealPreference?.label ?? person.selectedMealTypeId ?? ''),
          xls.TextCellValue(party.totalCount.toString()),
        ]);
      }
    }

    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');
    book.setDefaultSheet('Guest List');

    final bytes = book.encode();
    if (bytes == null) {
      throw Exception('Failed to encode Excel file');
    }
    await _shareBytes(
      bytes,
      'event_guests_${_safe(eventName)}_${_stamp()}.xlsx',
      'Guest Export — $eventName',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _shareBytes(
      List<int> bytes, String fileName, String subject) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], subject: subject);
  }

  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  String _stamp() => DateTime.now().millisecondsSinceEpoch.toString();

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _formatDateTime(DateTime dt) =>
      "${_formatDate(dt)} ${TimeFormat.hm12('${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}')}";

  String _statusLabel(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'Present';
      case AttendanceStatus.absent:
        return 'Absent';
      case AttendanceStatus.skipped:
        return 'Skipped';
      case AttendanceStatus.pending:
        return 'Pending';
      case AttendanceStatus.onVacation:
        return 'On Vacation';
    }
  }

}

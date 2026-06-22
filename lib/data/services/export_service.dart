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
class ExportService {
  ExportService._();

  static final ExportService instance = ExportService._();

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
    final summaries = BillingService.summarize(rows);
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MealAttend — Attendance Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Group: $groupName${dateRangeLabel != null ? '  |  Period: $dateRangeLabel' : ''}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated: ${_formatDate(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Divider(),
          ],
        ),
        build: (context) => [
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
          pw.SizedBox(height: 18),
          pw.Text(
            'Billing Summary',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          ...summaries.map((s) => _pdfSummaryBlock(s, pricingEnabled)),
        ],
      ),
    );

    await _shareBytes(
      await pdf.save(),
      'attendance_${_safe(groupName)}_${_stamp()}.pdf',
      'Attendance Report — $groupName',
    );
  }

  pw.Widget _pdfSummaryBlock(BillingSummary s, bool pricingEnabled) {
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
            pw.Text(
              // PDF font lacks ₹ — use 'Rs '.
              'Total Bill: Rs ${s.totalBill}',
              style:
                  pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }

  // ── CSV ────────────────────────────────────────────────────────────────────

  Future<void> exportCsv({
    required List<AttendanceModel> records,
    required List<MealModel> meals,
    required String groupName,
    required bool pricingEnabled,
    required DateTime from,
    required DateTime to,
    String? dateRangeLabel,
    List<MealModel> todayMeals = const [],
    Set<String> vacationUserIds = const {},
  }) async {
    final rows = BillingService.buildRows(
        records: records,
        meals: meals,
        from: from,
        to: to,
        todayMeals: todayMeals,
        vacationUserIds: vacationUserIds);
    final summaries = BillingService.summarize(rows);
    final buffer = StringBuffer();

    buffer.writeln(_headers(pricingEnabled).map(_csvEscape).join(','));
    for (final r in rows) {
      buffer.writeln(_rowCells(r, groupName, pricingEnabled)
          .map(_csvEscape)
          .join(','));
    }

    buffer.writeln();
    buffer.writeln('Billing Summary');
    for (final s in summaries) {
      buffer.writeln(_csvEscape(s.userName));
      final consumed =
          s.consumedByMeal.entries.map((e) => '${e.key}: ${e.value}');
      for (final c in consumed) {
        buffer.writeln(',${_csvEscape(c)}');
      }
      buffer.writeln(
          ',Present: ${s.present},Skipped: ${s.skipped},Absent: ${s.absent},Total meals: ${s.totalMeals}');
      if (pricingEnabled) buffer.writeln(',Total Bill: ₹${s.totalBill}');
    }

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/attendance_${_safe(groupName)}_${_stamp()}.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
        subject: 'Attendance Export — $groupName');
  }

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
  }) async {
    final rows = BillingService.buildRows(
        records: records,
        meals: meals,
        from: from,
        to: to,
        todayMeals: todayMeals,
        vacationUserIds: vacationUserIds);
    final summaries = BillingService.summarize(rows);

    final book = xls.Excel.createExcel();
    final sheetName = 'Attendance';
    final sheet = book[sheetName];

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

    final sum = book['Billing Summary'];
    sum.appendRow([
      xls.TextCellValue('Name'),
      xls.TextCellValue('Present'),
      xls.TextCellValue('Skipped'),
      xls.TextCellValue('Absent'),
      xls.TextCellValue('Total Meals'),
      if (pricingEnabled) xls.TextCellValue('Total Bill'),
    ]);
    for (final s in summaries) {
      sum.appendRow([
        xls.TextCellValue(s.userName),
        xls.TextCellValue('${s.present}'),
        xls.TextCellValue('${s.skipped}'),
        xls.TextCellValue('${s.absent}'),
        xls.TextCellValue('${s.totalMeals}'),
        if (pricingEnabled) xls.TextCellValue('₹${s.totalBill}'),
      ]);
    }

    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');
    book.setDefaultSheet(sheetName);

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
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'MealAttend — Event Guest Report',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Event: $eventName${eventDateLabel != null ? '  |  Date: $eventDateLabel' : ''}',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Guests: $totalGuests  |  Adults: $totalAdults  |  Children: $totalChildren'
              '  |  Veg: $totalVeg  |  Non-Veg: $totalNonVeg',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated: ${_formatDate(DateTime.now())}',
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

  Future<void> exportEventGuestsCsv({
    required List<EventGuestParty> parties,
    required String eventName,
    String? eventDateLabel,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Party,Name,Type,Attendance,Meal Preference,Party Total');

    for (final party in parties) {
      for (final person in party.persons) {
        buffer.writeln([
          _csvEscape(party.primaryName),
          _csvEscape(person.displayName),
          person.isAdult ? 'Adult' : 'Child',
          person.isPresent ? 'Present' : 'Absent',
          _csvEscape(
              person.mealPreference?.label ?? person.selectedMealTypeId ?? ''),
          party.totalCount.toString(),
        ].join(','));
      }
    }

    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/event_guests_${_safe(eventName)}_${_stamp()}.csv');
    await file.writeAsString(buffer.toString());
    await Share.shareXFiles([XFile(file.path, mimeType: 'text/csv')],
        subject: 'Guest Export — $eventName');
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

  String _csvEscape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:smart_meal_management/features/events/models/event_guest_party.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';

/// Service that builds PDF or CSV exports of attendance records and shares
/// them via the platform share sheet ([share_plus]).
class ExportService {
  ExportService._();

  static final ExportService instance = ExportService._();

  // ── PDF ────────────────────────────────────────────────────────────────────

  /// Generates a PDF attendance report and opens the share sheet.
  Future<void> exportPdf({
    required List<AttendanceModel> records,
    required String groupName,
    String? dateRangeLabel,
  }) async {
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
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
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
            // Issue #11: every record carries Student + Group + Meal identity.
            headers: const [
              'Student',
              'Group',
              'Meal',
              'Status',
              'Preference',
              'Date',
              'Marked Time',
            ],
            data: records.map((r) => [
              r.userName ?? r.userId,
              groupName,
              r.mealName ?? '—',
              _statusLabel(r.status),
              r.preference ?? '—',
              _formatDate(r.date),
              r.markedAt != null ? _formatDateTime(r.markedAt!) : '—',
            ]).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.indigo100,
            ),
            rowDecoration: const pw.BoxDecoration(),
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColors.grey100,
            ),
            border: pw.TableBorder.all(
              color: PdfColors.grey400,
              width: 0.5,
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final fileName =
        'attendance_${groupName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Attendance Report — $groupName',
    );
  }

  // ── CSV ────────────────────────────────────────────────────────────────────

  /// Generates a CSV attendance export and opens the share sheet.
  Future<void> exportCsv({
    required List<AttendanceModel> records,
    required String groupName,
    String? dateRangeLabel,
  }) async {
    final buffer = StringBuffer();

    // Header — Issue #11: human-readable identity columns.
    buffer.writeln(
        'Student Name,Group Name,Meal Name,Status,Preference,Date,Marked Time');

    for (final r in records) {
      buffer.writeln([
        _csvEscape(r.userName ?? r.userId),
        _csvEscape(groupName),
        _csvEscape(r.mealName ?? ''),
        _statusLabel(r.status),
        _csvEscape(r.preference ?? ''),
        _formatDate(r.date),
        r.markedAt != null ? _formatDateTime(r.markedAt!) : '',
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final fileName =
        'attendance_${groupName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Attendance Export — $groupName',
    );
  }

  // ── Event Guest Export ─────────────────────────────────────────────────────

  /// Generates a PDF guest report for an event and opens the share sheet.
  Future<void> exportEventGuestsPdf({
    required List<EventGuestParty> parties,
    required String eventName,
    String? eventDateLabel,
  }) async {
    final pdf = pw.Document();

    // Flatten all persons for the detailed table
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

    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final fileName =
        'event_guests_${eventName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Guest Report — $eventName',
    );
  }

  /// Generates a CSV guest export for an event and opens the share sheet.
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
    final fileName =
        'event_guests_${eventName.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Guest Export — $eventName',
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _formatDateTime(DateTime dt) =>
      '${_formatDate(dt)} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

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

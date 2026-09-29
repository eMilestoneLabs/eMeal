import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:smart_meal_management/core/config/env_config.dart';
import 'package:smart_meal_management/core/constants/app_constants.dart';
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

/// Live-Test-16 ISSUE-16 (+ ISSUE-1): one itemised billing-ledger adjustment
/// for exports — so the PDF/Excel show each entry WITH its audit-trail
/// reason instead of only a per-member total. Plain data (isolate-safe).
class ExportAdjustment {
  const ExportAdjustment({
    required this.userId,
    required this.date,
    required this.type,
    required this.amountPaise,
    required this.reason,
    required this.status,
  });

  final String userId;

  /// Business date, YYYY-MM-DD (server `entryDate`).
  final String date;

  /// credit | debit | refund.
  final String type;

  /// Ledger minor units (paise), as stored.
  final int amountPaise;
  final String reason;

  /// posted | pending | rejected.
  final String status;

  factory ExportAdjustment.fromApi(Map<String, dynamic> j) => ExportAdjustment(
        userId: (j['userId'] ?? '').toString(),
        date: (j['entryDate'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        amountPaise: (j['amount'] as num?)?.toInt() ?? 0,
        reason: (j['reason'] ?? '').toString(),
        status: (j['status'] ?? 'posted').toString(),
      );

  /// REF-001 sign convention: a credit lowers the bill; debit and refund
  /// raise it (a refund consumes credit — never a discount).
  bool get lowersBill => type == 'credit';

  String get typeLabel => switch (type) {
        'credit' => 'Credit',
        'debit' => 'Debit',
        'refund' => 'Refund',
        _ => type,
      };

  String get statusLabel => switch (status) {
        'posted' => 'Posted',
        'pending' => 'Pending',
        'rejected' => 'Rejected',
        _ => status,
      };

  /// dd/MM/yyyy for display.
  String get dateLabel {
    final p = date.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : date;
  }

  /// Signed ₹ label. UNIT BOUNDARY (guidebook §3c): paise → ₹ happens ONLY
  /// here, at the export boundary, for display — totals are untouched.
  String amountLabel(String currency) =>
      '${lowersBill ? '-' : '+'}$currency${(amountPaise / 100).toStringAsFixed(2)}';
}

class ExportService {
  ExportService._();

  /// Live-Test-16 ISSUE-11: optional brand logo (PNG/JPEG bytes) for the PDF
  /// header's logo slot. Null → the built-in "MA" monogram is drawn. Set once
  /// at startup when the final logo asset is supplied; nothing else changes.
  static Uint8List? brandLogo;

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
    // Live-Test-8 ISSUE-005 (server parity): Present always bills; a REAL
    // Skipped record always bills (it exists only for dates whose Bill-Skip
    // policy was ON at close — the flag is not consulted). Live-Test-11
    // ISSUE-017: an Absent row bills only when its own write-time snapshot
    // (r.billAbsent) says the Bill-Absent toggle was ON — date-forward,
    // identical to the server engine. Virtual placeholder rows (autoSkipped)
    // never bill. The params are retained for call-site compatibility but no
    // longer affect the math.
    bool billSkippedMeals = false,
    bool? billAbsentMeals,
  }) {
    final billed = r.status == AttendanceStatus.present ||
        (!r.autoSkipped && r.status == AttendanceStatus.skipped) ||
        (r.status == AttendanceStatus.absent && r.billAbsent == true);
    return [
      r.userName,
      groupName,
      r.mealName,
      _statusLabel(r.status),
      r.preference ?? '',
      if (pricingEnabled)
        (billed ? '$currency${r.price ?? 0}' : '${currency}0'),
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
    // Live-Test-16 ISSUE-16: itemised ledger adjustments (with reason).
    List<ExportAdjustment> adjustments = const [],
    // SRS Module 03 (survey Q17/Q22): group Bill-Skip policy — bills
    // Skipped rows at their scheduled price when true.
    bool billSkippedMeals = false,
    // Live-Test-7 ISSUE-4: independent Absent policy (null = follow Skip).
    bool? billAbsentMeals,
    // Live-Test-15 ISSUE-3: rows/summaries the CALLER already computed (the
    // preview screen computes exactly these to render itself). Supplying them
    // removes a full duplicate O(members x meals x days) pass on the UI thread.
    // Omit them and the original self-computing behaviour is used unchanged.
    List<BillingRow>? precomputedRows,
    List<BillingSummary>? precomputedSummaries,
  }) async {
    // Issue 3 & 7: pass today's published overlay + vacation members so exported
    // billing matches the on-screen figures (per-day window auto-skip + vacation
    // exclusion) instead of the master-window / no-vacation fallback.
    final rows = precomputedRows ??
        BillingService.buildRows(
          records: records,
          meals: meals,
          from: from,
          to: to,
          todayMeals: todayMeals,
          vacationUserIds: vacationUserIds,
        );
    final summaries = precomputedSummaries ??
        BillingService.summarize(rows,
            billSkippedMeals: billSkippedMeals,
            billAbsentMeals: billAbsentMeals);

    // ISSUE-3: serialization (layout + render of every page) is the heavy
    // stage. Above the configured row threshold it runs in a BACKGROUND
    // ISOLATE so the UI thread keeps producing frames — the app no longer
    // freezes. Below it, the direct call is cheaper than the isolate spawn.
    final job = _PdfJob(
      rows: rows,
      summaries: summaries,
      groupName: groupName,
      pricingEnabled: pricingEnabled,
      dateRangeLabel: dateRangeLabel,
      financialsByUser: financialsByUser,
      billSkippedMeals: billSkippedMeals,
      billAbsentMeals: billAbsentMeals,
      adjustments: adjustments,
      logo: brandLogo,
    );
    final bytes = rows.length >= EnvConfig.current.exportIsolateRowThreshold
        ? await compute(_buildPdfBytesWorker, job)
        : await _buildPdfBytes(job);

    await _shareBytes(
      bytes,
      'attendance_${_safe(groupName)}_${_stamp()}.pdf',
      'Attendance Report — $groupName',
    );
  }

  /// Pure document build + serialize. No platform channels, no plugin access
  /// (this codebase loads NO custom fonts, so the built-in Helvetica metrics
  /// are used) — which is exactly what makes it isolate-safe.
  Future<Uint8List> _buildPdfBytes(_PdfJob job) async {
    final rows = job.rows;
    final summaries = job.summaries;
    final groupName = job.groupName;
    final pricingEnabled = job.pricingEnabled;
    final dateRangeLabel = job.dateRangeLabel;
    final financialsByUser = job.financialsByUser;
    final billSkippedMeals = job.billSkippedMeals;
    final billAbsentMeals = job.billAbsentMeals;
    final pdf = pw.Document();

    // Live-Test-16 ISSUE-16: member names for the itemised adjustments.
    final nameOf = {for (final s in summaries) s.userId: s.userName};
    final adjustments = List<ExportAdjustment>.of(job.adjustments)
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0
            ? d
            : (nameOf[a.userId] ?? '').compareTo(nameOf[b.userId] ?? '');
      });

    pdf.addPage(
      pw.MultiPage(
        // Live-Test-16: full-range reports exceed the package's 20-page
        // default (TooManyPagesException → "Export failed").
        maxPages: AppConstants.reportPdfMaxPages,
        // FR-EXP-042 + Live-Test-16 ISSUE-11: polished brand theme (hologram
        // watermark, header band with logo slot, "Powered by eMilestone").
        pageTheme: _polishedPageTheme(),
        footer: _polishedFooter,
        header: (context) => _polishedHeader(
          title: 'Attendance & Billing Report',
          scopeLabel: 'Group: $groupName',
          periodLabel: dateRangeLabel,
          logo: job.logo,
        ),
        // FR-EXP-041 (ISSUE-14): Summary FIRST, detailed line-items second.
        build: (context) => [
          _sectionTitle('Billing Summary'),
          ...summaries.map((s) =>
              _pdfSummaryBlock(s, pricingEnabled, financialsByUser[s.userId])),
          pw.SizedBox(height: 14),
          _sectionTitle('Detailed Records'),
          _polishedTable(
            headers: _headers(pricingEnabled),
            data: rows
                .map((r) => _rowCells(r, groupName, pricingEnabled,
                        currency: 'Rs ',
                        billSkippedMeals: billSkippedMeals,
                        billAbsentMeals: billAbsentMeals)
                    .map(_pdfCell)
                    .toList())
                .toList(),
            columnWidths: _detailColumnWidths(pricingEnabled),
            alignments: _detailAlignments(pricingEnabled),
            statusColumn: 3,
          ),
          // Live-Test-16 ISSUE-16 / ISSUE-1: every adjustment itemised with
          // its audit-trail reason (the summary keeps the signed total).
          if (pricingEnabled && adjustments.isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _sectionTitle('Adjustments'),
            _polishedTable(
              headers: const [
                'Date', 'Member', 'Type', 'Amount', 'Reason', 'Status',
              ],
              data: adjustments
                  .map((a) => [
                        a.dateLabel,
                        nameOf[a.userId] ?? a.userId,
                        a.typeLabel,
                        a.amountLabel('Rs '),
                        a.reason,
                        a.statusLabel,
                      ].map(_pdfCell).toList())
                  .toList(),
              columnWidths: const {
                0: pw.FlexColumnWidth(1.2),
                1: pw.FlexColumnWidth(2.0),
                2: pw.FlexColumnWidth(1.0),
                3: pw.FlexColumnWidth(1.3),
                4: pw.FlexColumnWidth(2.8),
                5: pw.FlexColumnWidth(1.0),
              },
              alignments: const {
                0: pw.Alignment.center,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                5: pw.Alignment.center,
              },
            ),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  // ── Live-Test-16 ISSUE-11: polished PDF building blocks ──────────────────
  //
  // Styling only — the SAME data, sections and order as before. Used by the
  // attendance/billing report; the event-guest PDF keeps its own theme.
  // Built-in Helvetica only (no font asset) so isolate builds stay intact.

  static const PdfColor _brandInk = PdfColor.fromInt(0xFF3730A3); // indigo-800
  static const PdfColor _brandPrimary = PdfColor.fromInt(0xFF4F46E5);
  static const PdfColor _brandAccent = PdfColor.fromInt(0xFF7C3AED);
  static const PdfColor _zebra = PdfColor.fromInt(0xFFF5F6FB);
  static const PdfColor _rule = PdfColor.fromInt(0xFFE2E4EE);
  static const PdfColor _muted = PdfColor.fromInt(0xFF6B7280);

  /// Empty values render as a plain "-" (never blank, never an em dash).
  static String _pdfCell(Object? v) {
    final s = (v ?? '').toString().trim();
    return (s.isEmpty || s == '—' || s == '–') ? '-' : s;
  }

  pw.PageTheme _polishedPageTheme() => pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 24),
        // "Hologram" watermark: two offset low-opacity layers (indigo +
        // violet) of the MealAttend mark — a subtle holographic sheen that
        // never competes with the data.
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Center(
            child: pw.Transform.rotate(
              angle: 0.55,
              child: pw.Stack(
                alignment: pw.Alignment.center,
                children: [
                  pw.Opacity(
                    opacity: 0.045,
                    child: pw.Text('MealAttend',
                        style: pw.TextStyle(
                            fontSize: 92,
                            fontWeight: pw.FontWeight.bold,
                            color: _brandPrimary)),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 6, top: 6),
                    child: pw.Opacity(
                      opacity: 0.03,
                      child: pw.Text('MealAttend',
                          style: pw.TextStyle(
                              fontSize: 92,
                              fontWeight: pw.FontWeight.bold,
                              color: _brandAccent)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// Logo slot: the supplied brand logo, else the "MA" monogram.
  pw.Widget _logoSlot(Uint8List? logo) => pw.Container(
        width: 34,
        height: 34,
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        padding: const pw.EdgeInsets.all(4),
        alignment: pw.Alignment.center,
        child: logo != null
            ? pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain)
            : pw.Text('MA',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: _brandPrimary)),
      );

  pw.Widget _polishedHeader({
    required String title,
    required String scopeLabel,
    String? periodLabel,
    Uint8List? logo,
  }) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: pw.BoxDecoration(
          borderRadius: pw.BorderRadius.circular(10),
          gradient: const pw.LinearGradient(
            colors: [_brandInk, _brandPrimary, _brandAccent],
          ),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _logoSlot(logo),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MealAttend',
                      style: pw.TextStyle(
                          fontSize: 8,
                          letterSpacing: 1.2,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 1),
                  pw.Text(title,
                      style: pw.TextStyle(
                          fontSize: 15,
                          color: PdfColors.white,
                          fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 3),
                  // FR-EXP-043: scope + period + timezone + generated-at.
                  pw.Text(
                    _metaLine(scopeLabel: scopeLabel, periodLabel: periodLabel),
                    style: const pw.TextStyle(
                        fontSize: 7.5, color: PdfColors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  pw.Widget _polishedFooter(pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.8)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.RichText(
              text: pw.TextSpan(children: [
                pw.TextSpan(
                    text: 'MealAttend',
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _brandPrimary)),
                const pw.TextSpan(
                    text: '  ·  Powered by ',
                    style: pw.TextStyle(fontSize: 8, color: _muted)),
                pw.TextSpan(
                    text: 'eMilestone',
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _brandAccent)),
              ]),
            ),
            pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
        ),
      );

  pw.Widget _sectionTitle(String text) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.only(left: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(left: pw.BorderSide(color: _brandPrimary, width: 3)),
        ),
        child: pw.Text(text,
            style: pw.TextStyle(
                fontSize: 12.5,
                fontWeight: pw.FontWeight.bold,
                color: _brandInk)),
      );

  /// Status → readable colour (text only; printing stays legible in mono).
  static PdfColor _statusColor(String s) => switch (s) {
        'Present' => const PdfColor.fromInt(0xFF15803D),
        'Absent' => const PdfColor.fromInt(0xFFB91C1C),
        'Skipped' => const PdfColor.fromInt(0xFFB45309),
        'On Vacation' => const PdfColor.fromInt(0xFF6D28D9),
        _ => PdfColors.grey800,
      };

  pw.Widget _polishedTable({
    required List<String> headers,
    required List<List<String>> data,
    required Map<int, pw.TableColumnWidth> columnWidths,
    Map<int, pw.Alignment> alignments = const {},
    int? statusColumn,
  }) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        columnWidths: columnWidths,
        cellAlignment: pw.Alignment.centerLeft,
        cellAlignments: alignments,
        headerAlignment: pw.Alignment.centerLeft,
        headerAlignments: alignments,
        headerPadding:
            const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        headerStyle: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: _brandPrimary),
        cellStyle: const pw.TextStyle(fontSize: 7.8, color: PdfColors.grey900),
        oddRowDecoration: const pw.BoxDecoration(color: _zebra),
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _rule, width: 0.5),
          bottom: pw.BorderSide(color: _rule, width: 0.5),
        ),
        textStyleBuilder: statusColumn == null
            ? null
            : (index, value, rowNum) => index == statusColumn && rowNum > 0
                ? pw.TextStyle(
                    fontSize: 7.8,
                    fontWeight: pw.FontWeight.bold,
                    color: _statusColor(value.toString()))
                : null,
      );

  /// Detail columns: Name, Group, Meal, Status, Preference, [Price], Date,
  /// Attendance Marked Time — proportional widths so long names wrap
  /// instead of squeezing the numeric columns.
  Map<int, pw.TableColumnWidth> _detailColumnWidths(bool pricing) {
    final flex = <double>[
      2.0, 1.5, 1.3, 1.1, 1.9,
      if (pricing) 1.0,
      1.2, 1.7,
    ];
    return {
      for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i]),
    };
  }

  Map<int, pw.Alignment> _detailAlignments(bool pricing) => {
        3: pw.Alignment.center,
        if (pricing) 5: pw.Alignment.centerRight,
        pricing ? 6 : 5: pw.Alignment.center,
        pricing ? 7 : 6: pw.Alignment.center,
      };

  pw.Widget _pdfSummaryBlock(
    BillingSummary s,
    bool pricingEnabled,
    MemberExportFinancials? fin,
  ) {
    final consumed = s.consumedByMeal.entries
        .map((e) => '${e.key}: ${e.value}')
        .join('   ·   ');

    pw.Widget stat(String label, int value, PdfColor color) => pw.Container(
          margin: const pw.EdgeInsets.only(right: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: _rule, width: 0.6),
          ),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(
                  text: '$label ',
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
              pw.TextSpan(
                  text: '$value',
                  style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: color)),
            ]),
          ),
        );

    pw.Widget money(String label, String value, {bool strong = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(label,
                    style: pw.TextStyle(
                        fontSize: strong ? 9.5 : 8.5,
                        fontWeight:
                            strong ? pw.FontWeight.bold : pw.FontWeight.normal,
                        color: strong ? _brandInk : PdfColors.grey800)),
              ),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: strong ? 10.5 : 8.5,
                      fontWeight: strong ? pw.FontWeight.bold : null,
                      color: strong ? _brandInk : PdfColors.grey900)),
            ],
          ),
        );

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        color: _zebra,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: _rule, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(s.userName,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10.5,
                  color: _brandInk)),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            stat('Present', s.present, const PdfColor.fromInt(0xFF15803D)),
            stat('Skipped', s.skipped, const PdfColor.fromInt(0xFFB45309)),
            stat('Absent', s.absent, const PdfColor.fromInt(0xFFB91C1C)),
            stat('Total meals', s.totalMeals, _brandInk),
          ]),
          if (consumed.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(consumed,
                style: const pw.TextStyle(fontSize: 8, color: _muted)),
          ],
          if (pricingEnabled) ...[
            pw.SizedBox(height: 5),
            pw.Container(height: 0.6, color: _rule),
            pw.SizedBox(height: 4),
            if (fin == null || !fin.hasAny)
              // PDF font lacks ₹ — use 'Rs '.
              money('Total Bill', 'Rs ${s.totalBill}', strong: true)
            else ...[
              // Host-inclusive breakdown — identical to the billing screens.
              money('Meals', 'Rs ${s.totalBill}'),
              if (fin.guestAmount != 0)
                // Plain "-": the built-in PDF font cannot draw an em dash.
                money(
                    'Hosted guests (${fin.guestCount}) - billed to this host',
                    'Rs ${fin.guestAmount}'),
              if (fin.openingBalance != 0)
                money('Opening balance (carried forward)',
                    fin.openingLabel('Rs ')),
              if (fin.adjustmentsTotal != 0)
                money('Adjustments (credits / refunds)',
                    fin.adjustmentsLabel('Rs ')),
              money('Net Total',
                  MemberExportFinancials.net('Rs ', fin.netFor(s.totalBill)),
                  strong: true),
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
    // Live-Test-7 ISSUE-4: independent Absent policy (null = follow Skip).
    bool? billAbsentMeals,
    // Live-Test-16 ISSUE-16: itemised ledger adjustments (with reason).
    List<ExportAdjustment> adjustments = const [],
    // ISSUE-3: caller-supplied rows/summaries (see exportPdf) — skips a full
    // duplicate billing pass. Omit for the original self-computing behaviour.
    List<BillingRow>? precomputedRows,
    List<BillingSummary>? precomputedSummaries,
  }) async {
    final rows = precomputedRows ??
        BillingService.buildRows(
            records: records,
            meals: meals,
            from: from,
            to: to,
            todayMeals: todayMeals,
            vacationUserIds: vacationUserIds);
    final summaries = precomputedSummaries ??
        BillingService.summarize(rows,
            billSkippedMeals: billSkippedMeals,
            billAbsentMeals: billAbsentMeals);

    final job = _PdfJob(
      rows: rows,
      summaries: summaries,
      groupName: groupName,
      pricingEnabled: pricingEnabled,
      dateRangeLabel: dateRangeLabel,
      financialsByUser: financialsByUser,
      billSkippedMeals: billSkippedMeals,
      billAbsentMeals: billAbsentMeals,
      adjustments: adjustments,
    );
    final bytes = rows.length >= EnvConfig.current.exportIsolateRowThreshold
        ? await compute(_buildXlsxBytesWorker, job)
        : await _buildXlsxBytes(job);

    await _shareBytes(
      bytes,
      'attendance_${_safe(groupName)}_${_stamp()}.xlsx',
      'Attendance Export — $groupName',
    );
  }

  /// Pure workbook build + encode — isolate-safe (no plugin access).
  Future<Uint8List> _buildXlsxBytes(_PdfJob job) async {
    final rows = job.rows;
    final summaries = job.summaries;
    final groupName = job.groupName;
    final pricingEnabled = job.pricingEnabled;
    final dateRangeLabel = job.dateRangeLabel;
    final financialsByUser = job.financialsByUser;
    final billSkippedMeals = job.billSkippedMeals;
    final billAbsentMeals = job.billAbsentMeals;

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
        _rowCells(r, groupName, pricingEnabled,
                billSkippedMeals: billSkippedMeals,
                billAbsentMeals: billAbsentMeals)
            .map((c) => xls.TextCellValue(c))
            .toList(),
      );
    }

    // Live-Test-16 ISSUE-16 / ISSUE-1: one row per ledger adjustment, WITH
    // its audit-trail reason (the summary sheet keeps the signed total).
    if (pricingEnabled && job.adjustments.isNotEmpty) {
      final nameOf = {for (final s in summaries) s.userId: s.userName};
      final adjSheet = book['Adjustments'];
      brandBand(adjSheet);
      adjSheet.appendRow([
        xls.TextCellValue('Date'),
        xls.TextCellValue('Member'),
        xls.TextCellValue('Type'),
        xls.TextCellValue('Amount (₹)'),
        xls.TextCellValue('Reason'),
        xls.TextCellValue('Status'),
      ]);
      final sorted = List<ExportAdjustment>.of(job.adjustments)
        ..sort((a, b) => a.date.compareTo(b.date));
      for (final a in sorted) {
        adjSheet.appendRow([
          xls.TextCellValue(a.dateLabel),
          xls.TextCellValue(nameOf[a.userId] ?? a.userId),
          xls.TextCellValue(a.typeLabel),
          xls.TextCellValue(a.amountLabel('₹')),
          xls.TextCellValue(a.reason),
          xls.TextCellValue(a.statusLabel),
        ]);
      }
    }

    if (book.sheets.containsKey('Sheet1')) book.delete('Sheet1');
    book.setDefaultSheet('Billing Summary');

    final bytes = book.encode();
    if (bytes == null) {
      throw Exception('Failed to encode Excel file');
    }
    return Uint8List.fromList(bytes);
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
    // ISSUE-3: prune PREVIOUS exports before writing this one. Deliberately
    // NOT after the share: the receiving app (WhatsApp/Drive/mail) reads the
    // shared URI asynchronously once the sheet closes, so deleting the file we
    // just handed over could truncate or fail the send. Pruning on the next
    // run is race-free and bounds temp growth (files accumulated forever).
    unawaited(_pruneStaleExports(dir));
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], subject: subject);
  }

  /// Best-effort cleanup of exports older than [EnvConfig.exportTempTtl].
  /// Fully fail-soft: temp housekeeping must never break an export.
  Future<void> _pruneStaleExports(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(EnvConfig.current.exportTempTtl);
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        // Only ever touch files THIS service created.
        if (!_exportFilePattern.hasMatch(name)) continue;
        try {
          if ((await e.stat()).modified.isBefore(cutoff)) await e.delete();
        } catch (_) {
          // File vanished or is locked by the OS — skip it.
        }
      }
    } catch (_) {
      // Temp dir unreadable — nothing to prune, never surface to the user.
    }
  }

  /// Matches only this service's own generated exports, so pruning can never
  /// delete a file belonging to another feature sharing the temp directory.
  /// The random suffix group is OPTIONAL so exports written by builds from
  /// BEFORE the collision-safe stamp (`<name>_<ms>.pdf`) are also cleaned up —
  /// otherwise those legacy leftovers would linger in temp forever.
  static final RegExp _exportFilePattern =
      RegExp(r'^(attendance|event_guests)_.*_\d+(_[a-z0-9]+)?\.(pdf|xlsx)$');

  String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

  /// UNI-033: export filenames must never collide. millisecondsSinceEpoch
  /// alone collides when two exports land in the same millisecond, so a short
  /// random suffix is appended.
  String _stamp() =>
      '${DateTime.now().millisecondsSinceEpoch}_'
      '${(_rand.nextInt(1 << 32)).toRadixString(36)}';

  static final math.Random _rand = math.Random();

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

// ── ISSUE-3: isolate offload plumbing ────────────────────────────────────────

/// Immutable, isolate-transferable payload for a report build.
///
/// Holds ONLY plain data (strings, bools, nums, DateTimes, enums and lists of
/// them) so `compute` can copy it across the isolate boundary. Shared by the
/// PDF and XLSX builders — both render the same rows/summaries, so one payload
/// type serves both (DRY; no parallel duplicate class).
class _PdfJob {
  const _PdfJob({
    required this.rows,
    required this.summaries,
    required this.groupName,
    required this.pricingEnabled,
    required this.dateRangeLabel,
    required this.financialsByUser,
    required this.billSkippedMeals,
    required this.billAbsentMeals,
    this.adjustments = const [],
    this.logo,
  });

  final List<BillingRow> rows;
  final List<BillingSummary> summaries;
  final String groupName;
  final bool pricingEnabled;
  final String? dateRangeLabel;
  final Map<String, MemberExportFinancials> financialsByUser;
  final bool billSkippedMeals;
  final bool? billAbsentMeals;

  /// Live-Test-16 ISSUE-16: itemised adjustments (plain data, isolate-safe).
  final List<ExportAdjustment> adjustments;

  /// Live-Test-16 ISSUE-11: brand logo bytes for the header slot (optional).
  final Uint8List? logo;
}

/// Live-Test-16 ISSUE-11/16: test-only entry that runs the SAME private PDF /
/// XLSX builders the export uses (no share sheet, no platform channel), so a
/// render/layout error is caught by a test instead of on a device.
@visibleForTesting
Future<Uint8List> buildReportBytesForTest({
  required bool pdf,
  required List<BillingRow> rows,
  required List<BillingSummary> summaries,
  required bool pricingEnabled,
  Map<String, MemberExportFinancials> financialsByUser = const {},
  List<ExportAdjustment> adjustments = const [],
  Uint8List? logo,
}) {
  final job = _PdfJob(
    rows: rows,
    summaries: summaries,
    groupName: 'Test Group',
    pricingEnabled: pricingEnabled,
    dateRangeLabel: '01/09/2026 - 30/09/2026',
    financialsByUser: financialsByUser,
    billSkippedMeals: false,
    billAbsentMeals: null,
    adjustments: adjustments,
    logo: logo,
  );
  return pdf
      ? ExportService.instance._buildPdfBytes(job)
      : ExportService.instance._buildXlsxBytes(job);
}

/// Top-level isolate entry points (required by `compute`).
///
/// [ExportService] is a STATELESS singleton (private ctor, no mutable fields),
/// so resolving `instance` inside the worker isolate is safe and keeps every
/// existing layout/formatting method reachable unchanged — no rendering code
/// was duplicated or rewritten for the isolate path.
Future<Uint8List> _buildPdfBytesWorker(_PdfJob job) =>
    ExportService.instance._buildPdfBytes(job);

Future<Uint8List> _buildXlsxBytesWorker(_PdfJob job) =>
    ExportService.instance._buildXlsxBytes(job);

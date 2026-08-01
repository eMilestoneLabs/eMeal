import 'package:flutter/foundation.dart';
import 'package:smart_meal_management/data/services/billing_service.dart';
import 'package:smart_meal_management/data/services/export_service.dart';
import 'package:smart_meal_management/shared/models/attendance_model.dart';
import 'package:smart_meal_management/shared/models/meal_model.dart';

/// State manager for the export screen.
class ExportProvider extends ChangeNotifier {
  ExportProvider({ExportService? exportService})
      : _service = exportService ?? ExportService.instance;

  final ExportService _service;

  // ── State ──────────────────────────────────────────────────────────────────

  bool _isExporting = false;
  String? _error;
  String _exportFormat = 'pdf'; // 'pdf' | 'xlsx' (RPT-001: csv removed)
  bool _exportSuccess = false;

  // ── Getters ────────────────────────────────────────────────────────────────

  bool get isExporting => _isExporting;
  String? get error => _error;
  String get exportFormat => _exportFormat;
  bool get exportSuccess => _exportSuccess;
  bool get isPdf => _exportFormat == 'pdf';

  // ── Actions ────────────────────────────────────────────────────────────────

  void setFormat(String format) {
    // RPT-001: CSV export removed — Excel + PDF only.
    assert(format == 'pdf' || format == 'xlsx',
        'Format must be pdf or xlsx');
    if (_exportFormat == format) return;
    _exportFormat = format;
    notifyListeners();
  }

  Future<void> export({
    required List<AttendanceModel> records,
    required List<MealModel> meals,
    required String groupName,
    required bool pricingEnabled,
    required DateTime from,
    required DateTime to,
    String? dateRangeLabel,
    // Issue 4: members currently on vacation — excluded from billing/auto-skip
    // and surfaced as "On Vacation" in the export (ExportService handles both).
    Set<String> vacationUserIds = const {},
    // Guests + adjustments per member so exported summaries reconcile with
    // the billing screens (net = meals + guests + adjustments).
    Map<String, MemberExportFinancials> financialsByUser = const {},
    // SRS Module 03 (survey Q17/Q22): group Bill-Skip policy.
    bool billSkippedMeals = false,
    // Live-Test-7 ISSUE-4: independent Absent policy (null = follow Skip).
    bool? billAbsentMeals,
    // Live-Test-15 ISSUE-3: rows/summaries the preview already computed —
    // forwarded so the export does not repeat the full billing pass.
    List<BillingRow>? precomputedRows,
    List<BillingSummary>? precomputedSummaries,
  }) async {
    if (_isExporting) return;
    _isExporting = true;
    _error = null;
    _exportSuccess = false;
    notifyListeners();

    try {
      switch (_exportFormat) {
        case 'pdf':
          await _service.exportPdf(
            records: records,
            meals: meals,
            groupName: groupName,
            pricingEnabled: pricingEnabled,
            from: from,
            to: to,
            dateRangeLabel: dateRangeLabel,
            vacationUserIds: vacationUserIds,
            financialsByUser: financialsByUser,
            billSkippedMeals: billSkippedMeals,
            billAbsentMeals: billAbsentMeals,
            precomputedRows: precomputedRows,
            precomputedSummaries: precomputedSummaries,
          );
        // RPT-001: CSV export removed — Excel + PDF only.
        default: // 'xlsx'
          await _service.exportXlsx(
            records: records,
            meals: meals,
            groupName: groupName,
            pricingEnabled: pricingEnabled,
            from: from,
            to: to,
            dateRangeLabel: dateRangeLabel,
            vacationUserIds: vacationUserIds,
            financialsByUser: financialsByUser,
            billSkippedMeals: billSkippedMeals,
            billAbsentMeals: billAbsentMeals,
            precomputedRows: precomputedRows,
            precomputedSummaries: precomputedSummaries,
          );
      }
      _exportSuccess = true;
    } catch (e) {
      _error = 'Export failed: $e';
    } finally {
      _isExporting = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearSuccess() {
    _exportSuccess = false;
    notifyListeners();
  }
}
